# Comment (re)créer l'infra ? 

ATTENTION : A partir de la partie Terraform, ce n'est plus un manuel d'installation mais un rapport de construction. Il faudra par la suitre mettre ce rapport autre part et le remplacer ici par un manuel d'installation.  


**Image** : debian-13.5.0-amd64-netinst.iso  
**RAM** : 16 Go  
**Stockage** : 250 Go SSD  

## Le boot 

Je boot une clé usb avec rufus sur debian 13.5.0 en amd64 en net install. 

Je mets la langue en francais, clavier français. 

Nom de la machine : ``` pve01``` 

Domaine : ``` tezcat-app.fr``` 

Mot de passe root : "pve01-root" dans mon bitwarden

Nouvel utilisateur : ``` tezcatadmin```   
Mot de passe tezcatadmin : "pve01-tezcatadmin" dans mon bitwarden

Partitionnement : Utiliser un disque entier et je choisis le SSD de 250 Go
Tout dans une seule partition 

Sélection des logiciels : uniquement "serveur SSH" et "utilitaires usuels du système"

Et j'installe grub sur le meme SSD de 250 Go 

## Préconfiguration

Une fois l'ordinateur redémaré, je me connecte en root.

Mise a jours et installation ds paquets nécéssaires :
```
apt update && apt full upgrade -y && apt install sudo
```
Mise à l'heure :
```
timedatectl set-timezone Europe/Paris
timedatectl set-ntp true
timedatectl
```
Mappage du FQDN : 
```
nano /etc/hosts 
```
```
127.0.0.1        localhost
192.168.1.26     pve01.tezcat-app.fr pve01
```
Configuration d'une IP statique :
```
nano /etc/network/interfaces
``` 
```
auto enp1s0  
iface enp1s0 inet static  
    address 192.168.1.26/24  
    gateway 192.168.1.1  
```
Ajout de tezcatadmin en tant que sudoers :
```
usermod -aG sudo tezcatadmin
```
Sur mon poste administrateur je crée ma clée SSH : 
```
ssh-keygen -t ed25519 -C "matteo@tezcat" -f ~/.ssh/tezcat_ed25519
``` 
Et je configure ssh pour plus de facilité : 
``` 
nano .ssh/config 
``` 
``` 
Host pve01
    HostName 192.168.1.26
    User tezcatadmin
    IdentityFile .ssh\tezcat_ed25519
``` 

Deployement de la clé publique de l'administrateur sur pve01 : 
``` 
ssh-copy-id -i ~/.ssh/tezcat_ed25519.pub tezcatadmin@192.168.1.26
``` 

Je me connecte maintenant en tezcatadmin plus en root et j'utilise SUDO.  
Sécurisation du serveur SSH :
``` 
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
``` 
``` 
PermitRootLogin no
PasswordAuthentication no
``` 
Reboot : 
``` 
sudo systemctl restart ssh
``` 
Et j'installe fail2ban : 
``` 
sudo apt install -y fail2ban
``` 

Je vérifie si la virtualisation est activée dans mon bios : 
```
egrep -c '(vmx|svm)' /proc/cpuinfo
```
Cela doit renvoyer plus que 0. Sinon activer la virtualisation dans le BIOS.

## Installation de Proxmox

Téléchargement de la clé du dépôt : 
```
sudo wget https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
```

Ajout du dépôt Proxmox gratuit aux sources listes debian : 
```
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve trixie pve-no-subscription" | sudo tee /etc/apt/sources.list.d/pve-install-repo.list
```

Mises a jour : 
```
sudo apt update && sudo apt full-upgrade -y
```

Installation de Proxmox puis redémarrage : 
```
sudo apt install -y proxmox-default-kernel
reboot
```

Installation de Proxmox VE et des outils : 
```
sudo apt install -y proxmox-ve postfix open-iscsi chrony
```
Pour postfix je choisis local only. 

Accès a l'interface web via : ```https://192.168.1.26:8006```
Login/Password de l'hote root. 

## Configuration

### Réseau

Remplacer enp0s31f6 par vmrb0 : 
```
sudo nano /etc/network/interfaces
```
```
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# Interface physique — désormais sans IP, rattachée au bridge
iface enp0s31f6 inet manual

# Bridge management + WAN — porte l'IP de l'hôte
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.26/24
    gateway 192.168.1.1
    bridge-ports enp0s31f6
    bridge-stp off
    bridge-fd 0
    dns-nameservers 192.168.1.1 1.1.1.1
# Zone WAN
```

Maintenant, pour ne pas perdre la main : 
```
sudo ifreload -a
```
Sans fermer le terminal, je lance un autre terminal et teste une reconnexion ssh.
```
ssh pve01
``` 
Je redémarre et je vérifie :
```
sudo reboot
```
```
ip -br a          # vmbr0 doit être UP avec 192.168.1.26
ping -c2 192.168.1.1
```
Je raoute les autres réseaux : 
```
sudo nano /etc/network/interfaces
```
```
# --- Bridges de zone (segments internes, sans port physique ni IP hôte) ---

auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
# Zone DMZ

auto vmbr2
iface vmbr2 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
# Zone PROD

auto vmbr3
iface vmbr3 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
# Zone DMZCLIENT

auto vmbr4
iface vmbr4 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
# Zone TESTLAN
```
Recharger et verifier :
```
sudo ifreload -a
ip -br a
```
Résultat attendu : 
```
lo               UNKNOWN        127.0.0.1/8 ::1/128
enp0s31f6        UP
vmbr0            UP             192.168.1.26/24 fe80::1e1b:dff:fe98:bd59/64
vmbr1            UNKNOWN        fe80::b0cb:e5ff:fe66:1b0e/64
vmbr2            UNKNOWN        fe80::387d:94ff:fe8a:76bd/64
vmbr3            UNKNOWN        fe80::1cc6:31ff:fe63:bad0/64
vmbr4            UNKNOWN        fe80::bc01:1fff:fe1e:9750/64
```
Maintennat que tout est stable, je fait une petite backup : 
```
sudo cp /etc/network/interfaces /etc/network/interfaces.bak-$(date +%F)
```

Et la conf DNS a probablement sauté donc : 
```
# solution immédiate — ajoute un resolveur
echo "nameserver 192.168.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
```

### Stockage 

J'ai 3 disques : 
- SSD 250Go où est debian. 
- 2x HDD 1To où j'aimerais mettre Backup/Images/Templates

Je repere mes HDD :
```
lsblk -o NAME,SIZE,MODEL,MOUNTPOINT
```

Je formate mes deux disques HDD : 
```
sudo wipefs -a /dev/sda
sudo wipefs -a /dev/sdb
```

Je vais faire un RAID 1 entre les deux HDD (sda et sdb): 
```
Datacenter → pve01 → Disks → ZFS → Create: ZFS
```
Name : ```hd-mirror```  
RAID Level : ``` Mirror ```  
Compression : ```On```  
Chocher ```sda``` et ```sdb``` uniquement

Je crée un dataset  ZFS sur le disque pour acceuillir des fichiers comme les sauvegardes, les images iso et les templates.
```
sudo zfs create hdd-mirror/files
```
(Dans le terminal de pve01)

Je l'ajoute comme répertoire dans
```Datacenter → Storage → Add → Directory```.
ID : ```hdd-files```  
Directory :  ```/hdd-mirror/files```  
Content : ```Image ISO, Modèle de Container, Sauvegarde```

Maintenant comme le system de fichier debian est sur tout le ssd, il faut faire en sorte que ```local``` accepte de stocker des images disque qcow2 dans ```Datacenter → Storage → local → Edit → Content```rajouter Image Disque. 

Dans les sources listes apt il y a pve-entreprise, ca va mettre une erreur a chaque apt update donc je le vire : 
```
cat /etc/apt/sources.list.d/pve-enterprise.sources
```
Si il n'y a pas ```Enabled:``` :
```
echo "Enabled: false" | sudo tee -a /etc/apt/sources.list.d/pve-enterprise.sources
```

### Template Cloud-Init

Création du template de VM (pour booter debian une seule fois)

Je télécharge une template cloud-init debian 13 pour mes vm : 
```
cd /hdd-mirror/files/template/iso/
sudo wget https://cloud.debian.org/images/cloud/trixie/latest/
debian-13-genericcloud-amd64.qcow2
```

J'installe l'agent invité dans l'image : 
```
sudo apt install -y libguestfs-tools
sudo virt-customize -a debian-13-genericcloud-amd64.qcow2 \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent'
```

Création du template des VM : 
```
sudo qm create 9000 \
  --name debian13-cloudinit \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --serial0 socket --vga serial0 \
  --agent enabled=1
```

J'attache le disque telechargé a la VM : 
```
sudo qm importdisk 9000 debian-13-genericcloud-amd64.qcow2 local
```
Attention : Rester dans le répertoir ou on a téléchargé le qcow2. 

Je branche ce disque au controleur SCSI de la VM :
```
sudo qm set 9000 --scsi0 local:9000/vm-9000-disk-0.raw
```

J'ajoute le lecteur "cloud-init", un disque virtuel ou proxmox injectera hostname, ip, user, ssh-key :
```
sudo qm set 9000 --ide2 local:cloudinit
```

J'ajuste l'ordre de boot :
```
sudo qm set 9000 --boot order=scsi0
```

Je la convertis en template : 
```
sudo qm template 9000
```

### Terraform

Je crée un rôle proxmox sur-meusure pour Terraform (moindre-privilèges) : 
```
sudo pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.Audit VM.Allocate VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Audit VM.PowerMgmt SDN.Use Sys.Audit Pool.Audit Sys.Modify VM.GuestAgent.Audit"
```

Je crée un user dédié : 
```
sudo pveum user add terraform@pve
```

Je lui attribue son role : 
```
sudo pveum acl modify / -user terraform@pve -role TerraformProv
```

Je crée un API Tokens pour cet user :
```
sudo pveum user token add terraform@pve terraform-token --privsep 0
```

Je stocke ```full-tokenid``` et ```value``` dans bitwarden.

Sur mon pc utilisateur, j'installe terraform : 
```
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
terraform version
```

Structude du projet terraform : 
```
terraform/
├── provider.tf        # le provider bpg/proxmox + connexion à l'API
├── variables.tf       # déclaration des variables (token, node, etc.)
├── terraform.tfvars   # TES valeurs (token depuis Bitwarden) → dans .gitignore !
├── main.tf            # tes VM
└── .gitignore         # exclut tfvars + fichiers d'état
```

Je crée le dossier : 
```
mkdir terraform
```

Pour ```provider.tf```, je déclare le provider bgp/proxmox (traducteur entre terraform et proxmox) et la connexion à l'api proxmox : 
```
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"   # vérifie la dernière version sur le registry Terraform
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = true   # certificat auto-signé de Proxmox → toléré en R&D
}
```

Pour ```variables.tf```, je déclare les variables : 
```
variable "pve_endpoint" {
  type        = string
  description = "URL de l'API Proxmox"
}

variable "pve_api_token" {
  type        = string
  description = "Token API au format user@realm!tokenid=secret"
  sensitive   = true
}

locals {
  ssh_key   = trimspace(file(pathexpand("~/.ssh/tezcat_ed25519.pub")))
  template  = 9000
  node      = "pve01"
}
```

Pour ```terraform.tfvars```, je mets les variables sensibles (tokens...) : 
```
pve_endpoint  = "https://192.168.1.26:8006/"
pve_api_token = "terraform@pve!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Pour ```.gitignore```, j'exculs les extentions/répertoires des fichiers d'états et variables sensibles : 
```
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

Puis toujours dans le répo git j'initialise Terraform : 
```
terraform init
```

Et je teste une connexion au proxmox a vide : 
```
terraform plan
```

Pour ```main.tf``` là ou son crée les VM : 
```
resource "proxmox_virtual_environment_vm" "firewall" {
  name      = "firewall"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu    { cores = 1 }
  memory { dedicated = 1024 }

  # Démarre en premier : sans lui, aucune zone n'est routée
  startup { order = 1 }

  network_device { bridge = "vmbr0" }
  network_device { bridge = "vmbr1" }
  network_device { bridge = "vmbr2" }
  network_device { bridge = "vmbr3" }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.27/24"
        gateway = "192.168.1.1"
      }
    }
    ip_config {
      ipv4 { address = "10.1.0.254/24" }
    }
    ip_config {
      ipv4 { address = "10.2.0.254/24" }
    }
    ip_config {
      ipv4 { address = "10.3.0.254/24" }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "wireguard" {
  name      = "wireguard"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu    { cores = 1 }
  memory { dedicated = 1024 }

  startup { order = 2 }

  network_device { bridge = "vmbr1" }
  network_device { bridge = "vmbr3" }

  initialization {
    ip_config {
      ipv4 {
        address = "10.1.0.3/24"
        gateway = "10.1.0.254"
      }
    }
    ip_config {
      ipv4 { address = "10.3.0.1/24" }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "shield_test" {
  name      = "shield-test"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu    { cores = 2 }
  memory { dedicated = 2048 }

  network_device { bridge = "vmbr0" }
  network_device { bridge = "vmbr4" }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.28/24"
        gateway = "192.168.1.1"
      }
    }
    ip_config {
      ipv4 { address = "192.168.0.254/24" }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "edge" {
  name      = "edge"
  node_name = local.node
  clone { vm_id = local.template, full = true }
  cpu    { cores = 2 }
  memory { dedicated = 2048 }
  network_device { bridge = "vmbr1" }
  initialization {
    ip_config { ipv4 { address = "10.1.0.1/24", gateway = "10.1.0.254" } }
    user_account { username = "tezcatadmin", keys = [local.ssh_key] }
  }
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "gitlab" {
  name      = "gitlab"
  node_name = local.node
  clone { vm_id = local.template, full = true }
  cpu    { cores = 4 }
  memory { dedicated = 6144 }
  network_device { bridge = "vmbr2" }
  initialization {
    ip_config { ipv4 { address = "10.2.0.2/24", gateway = "10.2.0.254" } }
    user_account { username = "tezcatadmin", keys = [local.ssh_key] }
  }
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "elk" {
  name      = "elk"
  node_name = local.node
  clone { vm_id = local.template, full = true }
  cpu    { cores = 4 }
  memory { dedicated = 4096 }
  network_device { bridge = "vmbr2" }
  initialization {
    ip_config { ipv4 { address = "10.2.0.1/24", gateway = "10.2.0.254" } }
    user_account { username = "tezcatadmin", keys = [local.ssh_key] }
  }
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "app" {
  name      = "app"
  node_name = local.node
  clone { vm_id = local.template, full = true }
  cpu    { cores = 2 }
  memory { dedicated = 2048 }
  network_device { bridge = "vmbr2" }
  initialization {
    ip_config { ipv4 { address = "10.2.0.3/24", gateway = "10.2.0.254" } }
    user_account { username = "tezcatadmin", keys = [local.ssh_key] }
  }
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "ia" {
  name      = "ia"
  node_name = local.node
  clone { vm_id = local.template, full = true }
  cpu    { cores = 2 }
  memory { dedicated = 2048 }
  network_device { bridge = "vmbr3" }
  initialization {
    ip_config { ipv4 { address = "10.3.0.2/24", gateway = "10.3.0.254" } }
    user_account { username = "tezcatadmin", keys = [local.ssh_key] }
  }
  agent { enabled = true }
}

```

Lancement de la création des VM : 
```
terraform plan 
```

Puis si tout est ok : 
```
terraform apply 
```

### Ansible 

#### Firewall 

Je me connacte au firewall 
```
ssh tezcatadmin@192.168.1.27
```

J'installe nftables
```
sudo apt update && sudo apt install -y nftables
```

J'active l'ip forwarding. 
```
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-tezcat-fw.conf
```

(Sur mon PC) Copie du fichier de configuration nftables sur le firewall.
```
scp ansible/nftables.conf tezcatadmin@192.168.1.27:/tmp/nftables.conf
```

Sur le FW : 
```
sudo mv /tmp/nftables.conf /etc/nftables.conf
sudo chown root:root /etc/nftables.conf
sudo chmod 600 /etc/nftables.conf
```


J'applique la configuration : 
```
sudo nft -f /etc/nftables.conf
```

J'active la configuration : 
```
sudo systemctl enable nftables
```

Je n'oublie pas d'ajouter la route des VPN. 
```
sudo ip route add 10.0.0.0/16 via 10.1.0.3
```

#### Wireguard 

Je me connecte à la vm en SSH depuis le firewall.
```
ssh tezcatadmin@10.1.0.3 -i .ssh/tezcat_ed25519
```

J'installe wireguard.
```
sudo apt update && sudo apt install -y wireguard
```

Je génére la paire de clée du serveur.
```
sudo sh -c 'umask 077; wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key'
sudo cat /etc/wireguard/server_private.key   
sudo cat /etc/wireguard/server_public.key    
```

Configuration du serveur. 
```
sudo nano /etc/wireguard/wg0.conf
```
```
[Interface]
Address    = 10.0.0.1/24, 10.0.1.1/24, 10.0.2.1/24
ListenPort = 51820
PrivateKey = <server_private.key>

PostUp   = sysctl -w net.ipv4.ip_forward=1
PostUp   = iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth1 -j MASQUERADE

[Peer]
# Matteo — Admin
PublicKey  = <contenu de client_admin.pub>
AllowedIPs = 10.0.0.10/32
```
---
Sur le poste ADMIN : 

J'installe wireguard. 
```
sudo apt update && sudo apt install -y wireguard openresolv
```

Je génere une clée. Et la copie dans le fichier de configuration du serveur.
```
wg genkey | tee client_admin.key | wg pubkey > client_admin.pub
```

Configuration 
```
sudo nano /etc/wireguard/wg0.conf
```
```
[Interface]
PrivateKey = <client_admin.key>
Address    = 10.0.0.10/32
DNS        = 192.168.1.1

[Peer]
PublicKey  = <la clé PUBLIQUE du serveur>
Endpoint   = <TON_IP_PUBLIQUE>:51820
AllowedIPs = 10.1.0.0/24, 10.2.0.0/24, 10.3.0.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

Je la protège.
```
sudo chmod 600 /etc/wireguard/wg0.conf
```

Je monte le tunnel.
```
sudo wg-quick up wg0
```

---

Je lance le serveur.
```
sudo systemctl enable --now wg-quick@wg0
```

RESEAU D'ADMIN A PART ???

#### Durcissement des VMS

J'insalle Ansible sur mon pc administrateur 
```
sudo apt install -y ansible
```

Je monte le tunnel
```
sudo wg-quick up wg0
```
Je copie les fichiers inventory.ini, asible.cfg et harden.yml  
Je teste la connectivité : 
```
cd ansible/
ansible all_vms -m ping
```

#### Edge

Ajout d'une route pour le focntionnement de l'admiistration par vpn de facon permanente : 
```
sudo tee /etc/systemd/system/tezcat-route-vpn.service << 'EOF'
[Unit]
Description=Route retour vers les clients WireGuard
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ip route add 10.0.0.0/16 via 10.1.0.3
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tezcat-route-vpn.service
```

#### Gitlab 

#### IA

Ajout d'une route pour le focntionnement de l'admiistration par vpn de facon permanente : 
```
sudo tee /etc/systemd/system/tezcat-route-vpn.service << 'EOF'
[Unit]
Description=Route retour vers les clients WireGuard
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ip route add 10.0.0.0/16 via 10.3.0.1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tezcat-route-vpn.service
```