# TEZCAT — Guide d'accès pour les développeurs

Bienvenue ! Ce guide te permet d'accéder à l'infrastructure TEZCAT et de
travailler sur les dépôts GitLab.

> ⏱️ Compte 20 minutes pour tout mettre en place la première fois.

---

## Ce que tu dois avoir reçu de l'administrateur

- [ ] Ton **identifiant GitLab** (généralement `prenom.nom`)
- [ ] Un **mot de passe temporaire** GitLab (à changer immédiatement)
- [ ] La **clé publique du serveur WireGuard**
- [ ] L'**adresse du VPN** (IP publique ou nom de domaine) et le port `51820`
- [ ] Ton **adresse IP VPN attribuée** (dans la plage `10.0.1.x`)

Si l'un de ces éléments manque, demande-le avant de commencer.

---

## Étape 1 — Générer ta paire de clés WireGuard

> 🔑 **Règle absolue : ta clé PRIVÉE ne quitte JAMAIS ta machine.**
> Tu ne l'envoies à personne, jamais, sous aucun prétexte.
> Seule la clé **publique** (`.pub`) est transmise à l'administrateur.

### Installer WireGuard

**Linux (Debian/Ubuntu)**
```bash
sudo apt update && sudo apt install -y wireguard openresolv
```

**macOS**
```bash
brew install wireguard-tools
```

**Windows** — télécharger le client officiel sur wireguard.com/install

### Générer les clés

```bash
wg genkey | tee ~/tezcat_wg.key | wg pubkey > ~/tezcat_wg.pub
chmod 600 ~/tezcat_wg.key
```

### Envoyer TA CLÉ PUBLIQUE à l'administrateur

```bash
cat ~/tezcat_wg.pub
```
Copie cette ligne (elle ressemble à `xTd3...=`) et transmets-la à l'admin.
C'est cette clé qui te donnera accès au VPN.

⏸️ **Attends la confirmation de l'admin avant de passer à l'étape 2.**

---

## Étape 2 — Configurer ton tunnel VPN

Crée le fichier de configuration :

**Linux / macOS** → `/etc/wireguard/wg0.conf`
```bash
sudo nano /etc/wireguard/wg0.conf
```

```ini
[Interface]
PrivateKey = <le contenu de ton ~/tezcat_wg.key>
Address    = 10.0.1.XX/32          # ← l'IP que l'admin t'a attribuée

[Peer]
PublicKey  = <la clé publique du serveur, fournie par l'admin>
Endpoint   = <adresse VPN fournie par l'admin>:51820
AllowedIPs = 10.2.0.0/24           # accès GitLab uniquement
PersistentKeepalive = 25
```

Protège le fichier :
```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

**Windows** : ouvrir le client WireGuard → « Ajouter un tunnel » → « Ajouter un
tunnel vide », puis coller la configuration ci-dessus.

---

## Étape 3 — Monter le tunnel

```bash
sudo wg-quick up wg0        # connecter
sudo wg-quick down wg0      # déconnecter
```

**Vérifier que ça marche :**
```bash
sudo wg show
```
Tu dois voir une ligne `latest handshake` avec un temps récent (quelques secondes).
Si elle est absente, le tunnel n'est pas établi → voir la section Dépannage.

> 💡 Le tunnel n'affecte que l'accès à TEZCAT. Ta navigation internet
> habituelle continue de passer normalement.

---

## Étape 4 — Première connexion à GitLab

**Avec le tunnel monté**, ouvre dans ton navigateur :
```
https://10.2.0.2
```

⚠️ **Ton navigateur affichera un avertissement de sécurité** (« certificat non
valide »). C'est normal : le certificat est auto-signé, il n'y a pas de danger
sur ce réseau privé. Clique sur « Avancé » → « Continuer vers le site ».

**Connecte-toi** avec ton identifiant et le mot de passe temporaire.

### 🔴 Change ton mot de passe IMMÉDIATEMENT

`Avatar (en haut à droite) → Edit profile → Password`

Choisis un mot de passe **long et unique** (une phrase de passe de 4-5 mots est
idéale). Ne le réutilise nulle part ailleurs.

---

## Étape 5 — Configurer Git

### Ajouter ta clé SSH à GitLab (recommandé)

Si tu n'as pas encore de clé SSH :
```bash
ssh-keygen -t ed25519 -C "prenom@tezcat"
```

Puis copie ta clé publique :
```bash
cat ~/.ssh/id_ed25519.pub
```
Dans GitLab : `Avatar → Edit profile → SSH Keys` → colle la clé → « Add key ».

### Cloner un dépôt

**En SSH** (le port est `2222`, pas le port standard) :
```bash
git clone ssh://git@10.2.0.2:2222/tezcat/app.git
```

**En HTTPS** (nécessite de désactiver la vérification TLS à cause du certificat
auto-signé) :
```bash
git -c http.sslVerify=false clone https://10.2.0.2/tezcat/app.git
cd app && git config http.sslVerify false
```

---

## Les dépôts disponibles

| Dépôt | Contenu |
|-------|---------|
| `tezcat/infra` | Infrastructure as code (Terraform, Ansible) — *lecture seule pour les devs* |
| `tezcat/app` | Application web (front, back, API) |
| `tezcat/ai` | Moteur d'analyse et de décision |
| `tezcat/shield` | Appliance Shield (image, Filebeat, nftables) |

---

## Règles de contribution

- La branche `main` est **protégée** : tu ne peux pas y pousser directement.
- Travaille sur une **branche dédiée**, puis ouvre une **Merge Request**.
```bash
git checkout -b feat/ma-fonctionnalite
# ... travail ...
git push -u origin feat/ma-fonctionnalite
```
Puis ouvre la Merge Request depuis l'interface GitLab.

- **Ne commite JAMAIS de secret** (mot de passe, token, clé privée). En cas de
  doute, demande avant de pousser.

---

## Ce à quoi tu as accès

En tant que développeur, ton tunnel te donne accès à **GitLab uniquement**
(`10.2.0.2`). Les autres machines de l'infrastructure ne te sont pas accessibles,
c'est normal et voulu.

---

## Dépannage

| Problème | Solution |
|----------|----------|
| Pas de `latest handshake` dans `wg show` | Vérifie l'`Endpoint` et le port 51820. Teste depuis un autre réseau (partage 4G) pour écarter un blocage local. |
| Handshake OK mais GitLab inaccessible | Vérifie `AllowedIPs = 10.2.0.0/24` dans ta config. |
| `resolvconf: command not found` | `sudo apt install openresolv` |
| Avertissement certificat navigateur | Normal (auto-signé) — accepte l'exception. |
| `git push` refusé sur `main` | Normal : passe par une branche + Merge Request. |
| Mot de passe oublié | Contacte un administrateur. |

**Une question ? Un blocage ?** Contacte un administrateur plutôt que de
contourner un problème de sécurité.
