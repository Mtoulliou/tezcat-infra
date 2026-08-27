# TEZCAT — Guide d'accès pour les administrateurs

Ce guide te donne l'accès complet à l'infrastructure TEZCAT : VPN, GitLab,
Proxmox, et toutes les VM en SSH.

> ⏱️ Compte 30 minutes pour la mise en place initiale.
> ⚠️ Tu as un accès privilégié : lis la section « Responsabilités » en fin de document.

---

## Ce que tu dois avoir reçu

- [ ] Ton **identifiant GitLab** + mot de passe temporaire
- [ ] La **clé publique du serveur WireGuard**
- [ ] L'**adresse du VPN** et le port `51820`
- [ ] Ton **IP VPN attribuée** (plage admin `10.0.0.x`)

---

## Cartographie de l'infrastructure

### Zones réseau

| Zone | Bridge | Sous-réseau | Rôle |
|------|--------|-------------|------|
| Domestique | vmbr0 | 192.168.1.0/24 | Uplink (box) + management |
| DMZ | vmbr1 | 10.1.0.0/24 | Services exposés |
| PROD | vmbr2 | 10.2.0.0/24 | Services internes |
| DMZCLIENT | vmbr3 | 10.3.0.0/24 | Trafic lié aux clients |
| TESTLAN | vmbr4 | 192.168.0.0/24 | LAN client simulé |

**Passerelle de chaque zone interne : `.254`** (la VM firewall).

### Machines

| Machine | IP | Zone | Rôle |
|---------|-----|------|------|
| **pve01** | 192.168.1.26 | — | Hyperviseur Proxmox (UI : `:8006`) |
| **firewall** | 192.168.1.27 / 10.1.0.254 / 10.2.0.254 / 10.3.0.254 | toutes | Routage + nftables |
| **wireguard** | 10.1.0.3 / 10.3.0.1 | DMZ + DMZCLIENT | Bastion VPN |
| **edge** | 10.1.0.1 | DMZ | Nginx + Certbot + Web-Front |
| **gitlab** | 10.2.0.2 | PROD | GitLab CE (`:443`, SSH git `:2222`) |
| **elk** | 10.2.0.1 | PROD | Elasticsearch / Logstash / Kibana |
| **app** | 10.2.0.3 | PROD | Web-Back + PostgreSQL |
| **ia** | 10.3.0.2 | DMZCLIENT | Moteur d'analyse |
| **shield-test** | 192.168.1.28 / 192.168.0.254 | TESTLAN | Client simulé |

### Plages VPN par profil

| Profil | Plage | Accès |
|--------|-------|-------|
| **Admin** | 10.0.0.0/24 | Tout (GitLab, Kibana, Proxmox, SSH partout) |
| **Dev** | 10.0.1.0/24 | GitLab uniquement |
| **Shield** | 10.0.2.0/24 | ELK 5044 uniquement |

---

## Étape 1 — Clés WireGuard

> 🔑 **Ta clé privée ne quitte JAMAIS ta machine.** Seule la `.pub` est transmise.

```bash
sudo apt update && sudo apt install -y wireguard openresolv
wg genkey | tee ~/tezcat_wg.key | wg pubkey > ~/tezcat_wg.pub
chmod 600 ~/tezcat_wg.key
cat ~/tezcat_wg.pub        # ← à transmettre à l'admin qui t'enrôle
```

⏸️ Attends la confirmation avant de continuer.

---

## Étape 2 — Configurer le tunnel

`/etc/wireguard/wg0.conf` :
```ini
[Interface]
PrivateKey = <contenu de ~/tezcat_wg.key>
Address    = 10.0.0.XX/32          # ← IP attribuée (plage admin)
DNS        = 1.1.1.1

[Peer]
PublicKey  = <clé publique du serveur>
Endpoint   = <adresse VPN>:51820
AllowedIPs = 10.1.0.0/24, 10.2.0.0/24, 10.3.0.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
sudo wg-quick up wg0
sudo wg show               # vérifier le "latest handshake"
```

---

## Étape 3 — Clé SSH d'administration

La clé SSH permet l'accès aux VM (utilisateur `tezcatadmin`).

```bash
ssh-keygen -t ed25519 -C "prenom@tezcat" -f ~/.ssh/tezcat_ed25519
chmod 600 ~/.ssh/tezcat_ed25519
cat ~/.ssh/tezcat_ed25519.pub    # ← à transmettre à l'admin qui t'enrôle
```

> Mets une **passphrase** sur ta clé. Utilise `ssh-agent` pour ne pas la retaper :
> `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/tezcat_ed25519`

---

## Étape 3bis — Clé age (accès aux secrets chiffrés)

L'infrastructure gère ses secrets avec **SOPS + age** : ils sont versionnés dans
Git, mais chiffrés. Pour lancer un `terraform apply` (qui lit ces secrets), tu as
besoin de ta propre clé age.

### Installer les outils
```bash
sudo apt install -y age
# sops : binaire officiel (voir github.com/getsops/sops/releases pour la version)
SOPS_VERSION="v3.9.0"
curl -LO "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
sudo mv "sops-${SOPS_VERSION}.linux.amd64" /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops
```

### Générer ta clé
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt | grep "public key"    # ← clé PUBLIQUE à transmettre
```

> 🔑 Sauvegarde `keys.txt` dans ton gestionnaire de secrets personnel (Bitwarden
>    ou autre). Perdue, tu ne peux plus déchiffrer
>    aucun secret (il faudra qu'un autre admin re-chiffre pour ta nouvelle clé).
> 🔑 Transmets **uniquement la clé publique** (`age1...`) à l'admin qui t'enrôle.

### Une fois ta clé autorisée

Quand l'admin a ajouté ta clé publique au `.sops.yaml` et re-chiffré, tu peux :
```bash
sops --decrypt secrets/proxmox.yaml     # lire un secret
sops secrets/proxmox.yaml               # éditer un secret (re-chiffré à la sauvegarde)
```
Terraform lit les secrets automatiquement via le provider SOPS (ta clé est trouvée
à `~/.config/sops/age/keys.txt`).

> Détail complet dans `GUIDE_SOPS.md`.

---

## Étape 4 — Accès aux services

### GitLab
```
https://10.2.0.2
```
Avertissement certificat auto-signé → accepter l'exception.
🔴 **Change ton mot de passe temporaire immédiatement** :
`Avatar → Edit profile → Password`

Ajoute aussi ta clé SSH dans GitLab : `Avatar → Edit profile → SSH Keys`.

Clone (port `2222`) :
```bash
git clone ssh://git@10.2.0.2:2222/tezcat/infra.git
```

### Proxmox
```
https://192.168.1.26:8006
```
Realm **Linux PAM**, avec ton compte système.

### Kibana (quand ELK sera déployé)
```
http://10.2.0.1:5601
```

---

## Outils d'administration

L'infrastructure est **entièrement gérée en code**. Ne configure jamais à la main
ce qui est géré par Terraform ou Ansible — la modification serait écrasée.

```bash
git clone ssh://git@10.2.0.2:2222/tezcat/infra.git
cd infra
```

### Terraform (VM et GitLab)
```bash
cd terraform/           # VM Proxmox
terraform plan
terraform apply

cd terraform-gitlab/    # users, groupes, projets GitLab
terraform plan
terraform apply
```
> Les secrets (tokens Proxmox/GitLab) sont chiffrés dans `secrets/` via SOPS et
> déchiffrés automatiquement par ta clé age — rien à récupérer ailleurs.

### Ansible (configuration des VM)
```bash
cd ansible/
ansible all_vms -m ping           # test de connectivité

ansible-playbook harden.yml       # durcissement de base
ansible-playbook firewall.yml     # nftables + routage
ansible-playbook wireguard.yml    # bastion VPN
ansible-playbook docker.yml       # Docker sur les VM applicatives
ansible-playbook gitlab.yml       # stack GitLab
```

Toujours tester avec `--check` avant d'appliquer.

---

## Points de vigilance

**⚠️ Le firewall et le bastion WireGuard sont critiques.**
Une erreur de configuration peut couper l'accès à toute l'infrastructure.
Avant toute modification :
- Garde une **console Proxmox ouverte** (accès hors réseau, ton filet de sécurité)
- Teste en `--check` d'abord
- Sur nftables, prévois un flush de secours : `sudo sh -c 'sleep 300 && nft flush ruleset' &`

**⚠️ Ne jamais détruire l'infrastructure depuis le VPN.**
Un `terraform destroy` détruit la VM wireguard → le tunnel tombe → tu perds
l'accès en cours d'opération. Ces opérations se pilotent depuis **pve01**.

**⚠️ Le fichier `terraform.tfstate`** est l'état de l'infrastructure. Sans lui,
Terraform ne sait plus ce qu'il gère. Il n'est pas dans Git — sauvegarde-le.

---

## Responsabilités

En tant qu'administrateur, tu as accès à l'ensemble de l'infrastructure :

- **Ne partage jamais** tes clés privées (SSH, WireGuard, age) ni tes mots de passe.
- **Ne commite jamais de secret en clair** dans Git — les secrets passent par SOPS
  (la CI vérifie automatiquement qu'aucun secret en clair n'est poussé).
- Signale immédiatement toute suspicion de compromission (clé perdue, poste volé).
- Documente ce que tu modifies — l'infrastructure est en code, tout changement
  passe par un commit.

---

## Dépannage

| Problème | Piste |
|----------|-------|
| Pas de handshake WireGuard | Endpoint/port · tester depuis un autre réseau (4G) |
| Handshake OK mais VM injoignables | Route retour sur le firewall (`ip route show \| grep 10.0.0`) |
| `ping` ne répond pas entre zones | **Normal** : l'ICMP inter-zones n'est pas autorisé. Tester avec `nc -zv <ip> <port>` |
| GitLab inaccessible | `ssh gitlab "docker ps"` — le conteneur tourne-t-il ? |
| Terraform : `TLS handshake timeout` | Tunnel VPN tombé, ou GitLab arrêté |
| Accès perdu à une VM | Console Proxmox (`https://192.168.1.26:8006`) — accès hors réseau |
