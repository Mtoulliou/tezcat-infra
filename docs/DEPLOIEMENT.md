# TEZCAT — Déploiement complet (rebuild from scratch)

> Ordre pour reconstruire toute l'infrastructure depuis le code. Utile pour un
> nouveau déploiement, une reprise après incident, ou comprendre les dépendances.
>
> ⚠️ **Piloter depuis pve01** (réseau domestique), PAS depuis le VPN : un
> `terraform apply/destroy` touche la VM wireguard et couperait le tunnel en cours.

---

## Prérequis (sur la machine d'orchestration)

- Terraform, Ansible, sops, age installés.
- Clé age présente (`~/.config/sops/age/keys.txt`) pour déchiffrer les secrets.
- Clé SSH d'admin (`tezcat_ed25519`) et accès à pve01.
- Collections Ansible : `ansible-galaxy collection install community.general community.docker ansible.posix`.

---

## 1. Les VM (Terraform)

```bash
cd terraform
terraform init
terraform plan      # vérifier : création des 8 VM, aucun destroy inattendu
terraform apply
```
Le token Proxmox et l'endpoint sont lus via SOPS (`secrets/proxmox.yaml`).
Le template cloud-init `9000` injecte la clé SSH publique dans chaque VM.

## 2. Le réseau (Ansible) — ORDRE IMPORTANT

Le firewall doit router avant que le reste soit joignable.

```bash
cd ../ansible
ansible-playbook firewall.yml      # nftables + forwarding + route VPN
ansible-playbook wireguard.yml     # bastion + pairs + filtrage par profil
```

Récupérer la clé publique du serveur WG (change si la VM est recréée) :
```bash
ansible wireguard -m command -a "cat /etc/wireguard/server_public.key" --become
```
→ la mettre dans les configs clients, remonter les tunnels.

## 3. Durcissement + Docker

```bash
ansible-playbook harden.yml        # SSH, fail2ban, MAJ auto, clés admin, routes retour
ansible-playbook docker.yml        # Docker + Compose sur les VM applicatives
ansible all_vms -m ping            # valider : 7/7 joignables
```

## 4. GitLab + Runner

```bash
ansible-playbook gitlab.yml                                   # disque + stack GitLab
ansible-playbook runner.yml -e "runner_token=glrt-..."        # Runner (token créé dans l'UI)
```
Attendre 2-5 min (premier boot GitLab). Mot de passe root initial :
```bash
ssh tezcatadmin@10.2.0.2 "docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password"
```

## 5. Configuration GitLab (as-code)

```bash
cd ../terraform-gitlab
terraform init && terraform apply    # groupe, projets, users (secrets via SOPS)
```

## 6. Services métier

Chacun via son playbook dédié (voir la fiche du service dans `services/`) :
ELK, app, IA, shield.

---

## Ordre de démarrage (au boot de pve01)

Défini dans Terraform (`startup { order }`) : **firewall (1) → wireguard (2) →
le reste**. Sans le firewall, aucune zone n'est routée.

## En cas d'accès perdu

Console Proxmox : `https://192.168.1.26:8006` (hors réseau, ton filet de secours).
