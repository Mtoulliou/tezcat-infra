# Runbook — Gérer un pair WireGuard

> ⚠️ **`wg0.conf` est désormais géré par Ansible** (`ansible/wireguard.yml`).
> Ne plus l'éditer à la main sur le serveur : toute modification manuelle sera
> écrasée au prochain `ansible-playbook wireguard.yml`.
> Les pairs se déclarent **dans le playbook**, versionné dans Git.

> **Serveur WG :** VM `wireguard` · DMZ `10.1.0.3` · DMZCLIENT `10.3.0.1`
> **Principe :** le réseau (nftables + iptables) verrouille les accès — pas le DNS,
> pas les `AllowedIPs` côté client (éditables par l'utilisateur).

---

## Plan d'adressage des profils

| Profil | Plage VPN | Accès autorisé | Où c'est appliqué |
|--------|-----------|----------------|-------------------|
| **Admin**  | 10.0.0.0/24 | GitLab, Kibana, Proxmox, SSH partout | firewall + VM WG |
| **Dev**    | 10.0.1.0/24 | GitLab (22, 443) uniquement | firewall |
| **Shield** | 10.0.2.0/24 | ELK 5044 uniquement | firewall |

Une IP `/32` par pair, jamais partagée → révocation individuelle possible.
**Convention :** attribuer à partir de `.10` (`.1` = serveur).

---

## Ajouter un pair

### 1. Générer la paire de clés — côté CLIENT

Sur la machine du client (poste, laptop, appliance Shield) :

```bash
wg genkey | tee client_<nom>.key | wg pubkey > client_<nom>.pub
chmod 600 client_<nom>.key
```

> 🔑 **La clé privée ne quitte JAMAIS la machine du client.**
> Seule la clé `.pub` est transmise à l'administrateur.

### 2. Déclarer le pair dans le playbook — côté ADMIN

Éditer `ansible/wireguard.yml`, section `wg_peers` :

```yaml
    wg_peers:
      - name: "Matteo — Admin"
        public_key: "<clé publique existante>"
        allowed_ips: "10.0.0.10/32"

      # ← nouveau pair
      - name: "Prénom Nom — Dev"
        public_key: "<contenu de client_<nom>.pub>"
        allowed_ips: "10.0.1.10/32"      # IP libre dans la plage du profil
```

Points de vigilance :
- `allowed_ips` en **`/32`** → épingle le pair à une IP unique (c'est ce qui permet
  au firewall de l'identifier comme Admin / Dev / Shield).
- Choisir l'IP dans la **plage correspondant au profil**, sinon les règles nftables
  ne s'appliqueront pas.
- Vérifier que l'IP n'est pas déjà prise (tableau d'attribution en bas).

### 3. Appliquer

```bash
cd ansible/
ansible-playbook wireguard.yml --check     # vérifier ce qui va changer
ansible-playbook wireguard.yml             # appliquer
```

⚠️ Le playbook **redémarre `wg0`** → coupure brève des tunnels existants.
Garder la console Proxmox ouverte lors des premiers runs.

### 4. Fournir sa configuration au client

R�cupérer la **clé publique du serveur** (affichée en fin de playbook, ou) :

```bash
ansible wireguard -m command -a "cat /etc/wireguard/server_public.key" --become
```

Transmettre au client ce modèle (à compléter avec SA clé privée) :

```ini
[Interface]
PrivateKey = <SA clé privée — reste chez lui>
Address    = 10.0.1.10/32          # l'IP attribuée
# DNS      = 1.1.1.1               # nécessite openresolv côté client

[Peer]
PublicKey  = <clé publique du serveur>
Endpoint   = <IP publique ou vpn.tezcat-app.fr>:51820
AllowedIPs = 10.2.0.0/24           # ← selon le profil, voir ci-dessous
PersistentKeepalive = 25
```

**`AllowedIPs` côté client selon le profil :**

| Profil | AllowedIPs à fournir |
|--------|----------------------|
| Admin | `10.1.0.0/24, 10.2.0.0/24, 10.3.0.0/24, 192.168.1.0/24` |
| Dev | `10.2.0.0/24` (GitLab) |
| Shield | `10.2.0.0/24` (ELK) |

> ℹ️ Côté client, `AllowedIPs` n'est qu'une **table de routage** (éditable par
> l'utilisateur). Le vrai contrôle d'accès est appliqué par **nftables sur le
> firewall** et par les règles FORWARD du bastion.

### 5. Vérifier

Côté serveur :
```bash
ansible wireguard -m command -a "wg show" --become
```
Le nouveau pair doit apparaître, avec un `latest handshake` dès qu'il se connecte.

Côté client :
```bash
sudo wg-quick up wg0
sudo wg show                        # handshake présent ?
ping <une IP autorisée du profil>
```

---

## Révoquer un pair

1. **Supprimer son bloc** de `wg_peers` dans `ansible/wireguard.yml`.
2. Appliquer : `ansible-playbook wireguard.yml`
3. Vérifier : `ansible wireguard -m command -a "wg show" --become`
4. Commit dans Git (traçabilité de la révocation).

> Révocation **immédiate** : sans son bloc `[Peer]`, le serveur refuse le
> handshake, quelle que soit la config du client.

---

## Gestion des clés serveur

La clé privée du serveur est **générée sur l'hôte par le playbook** et n'en sort
jamais :
- Générée une seule fois (`when: not wg_privkey.stat.exists`) → jamais écrasée.
- Lue au déploiement via `slurp`, avec `no_log: true`.
- **Aucune clé privée dans Git**, aucune dans les variables Ansible.

Seules les **clés publiques** des pairs sont versionnées (non sensibles).

> Si la VM est détruite/recréée : la clé serveur change → redistribuer la nouvelle
> clé publique à tous les clients.

---

## Dépannage

| Symptôme | Piste |
|----------|-------|
| Pas de `latest handshake` | Port-forward `51820/UDP` sur la box · DNAT du firewall · CGNAT opérateur · Endpoint erroné |
| Handshake OK mais rien ne répond | Route retour manquante (`ip route replace 10.0.0.0/16 via 10.1.0.3` sur le firewall) · `AllowedIPs` client trop restrictif |
| Accès partiel (certaines VM seulement) | Règles nftables du firewall pour ce profil · routage asymétrique sur les VM DMZ/DMZCLIENT (route retour à poser sur la VM) |
| `resolvconf: command not found` (client) | `sudo apt install openresolv` ou commenter la ligne `DNS =` |
| Source vue comme `10.1.0.3` au lieu de `10.0.0.x` | Règle MASQUERADE résiduelle sur le bastion → à supprimer (elle casse le filtrage par profil) |

**Tester depuis l'extérieur (4G), pas depuis le réseau domestique** — le hairpin NAT
de la box fausse le diagnostic.

---

## Attribution des IP VPN

| IP | Profil | Titulaire | Date | Statut |
|----|--------|-----------|------|--------|
| 10.0.0.1 | — | Serveur WireGuard | — | actif |
| 10.0.0.10 | Admin | Matteo | — | actif |
| | | | | |

> Tenir ce tableau à jour à chaque ajout/révocation.
