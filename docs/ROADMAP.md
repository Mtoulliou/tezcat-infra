# TEZCAT — Roadmap & état d'avancement

> Document unique de suivi (fusion de l'ancien plan de migration et de la roadmap
> technique). Reflète où en est l'infrastructure et ce qui reste à faire.
>
> **Principe directeur depuis le début :** débloquer → durcir → déployer, et
> automatiser ce qui se répète. Pas de sur-ingénierie en R&D.

---

## Vue d'ensemble

| Domaine | État |
|---------|------|
| Hôte Proxmox + réseau segmenté (5 zones) | ✅ |
| 8 VM en Terraform (reproductible) | ✅ |
| Firewall nftables (routage + NAT + flux) | ✅ |
| Bastion WireGuard (profil admin) | ✅ |
| Ansible (harden, firewall, wireguard, docker) | ✅ |
| GitLab CE + config as-code + Runner | ✅ |
| Secrets chiffrés SOPS/age | ✅ |
| CI de validation | ✅ |
| Onboarding Max & Jules | ⏭️ **en cours** |
| Services métier (ELK, app, IA, shield) | ⬜ à venir |
| DNS + vrai certificat TLS | ⬜ reporté |
| Sauvegardes (restic) | ⬜ reporté |
| CI de déploiement + backend d'état | ⬜ quand l'équipe en aura besoin |

---

## ✅ Terminé

### Fondation infrastructure
- Hôte Proxmox `pve01` durci (SSH clé-only, fail2ban, unattended-upgrades).
- Réseau segmenté en 5 zones (vmbr0-4), stockage ZFS mirror pour les données.
- 8 VM déployées via Terraform (provider bpg/proxmox, token en moindre privilège).
- Infra reproductible : `terraform apply` recrée tout depuis le template cloud-init.

### Réseau & accès
- **Firewall nftables** : routage inter-zones, NAT, DNAT (80/443→edge, 51820→wg),
  policy drop par défaut, table de flux appliquée. Géré par `firewall.yml`.
- **Bastion WireGuard** : profil admin opérationnel, filtrage par profil (DMZ +
  DMZCLIENT), clé serveur générée sur l'hôte. Géré par `wireguard.yml`.
- Routage retour VPN persistant (services systemd, `ip route replace` idempotent).
- Reboots de test validés : tout remonte automatiquement.

### Automatisation (Ansible)
- Playbooks : `harden.yml`, `firewall.yml`, `wireguard.yml`, `docker.yml`.
- Clés SSH admin gérées en liste (`group_vars/all.yml`, `authorized_key exclusive`).
- Runbook d'ajout/révocation d'un pair WireGuard.

### GitLab (backbone)
- GitLab CE déployé (HTTPS auto-signé, disque de données dédié sur miroir HDD).
- Configuration as-code (Terraform gitlabhq/gitlab) : groupe `tezcat`, 4 projets
  (infra, ai, app, shield), utilisateurs admins.
- GitLab Runner (executor Docker, concurrent=1, limite 1g/job).
- CI de validation : terraform fmt/validate, ansible syntax-check, contrôle
  anti-secret-en-clair.

### Secrets (SOPS/age)
- Chiffrement multi-clés (une clé age par personne + Runner CI).
- Secrets migrés : token Proxmox, token GitLab, mot de passe initial des comptes.
- Provider `carlpett/sops` branché sur les deux projets Terraform.
- Plus aucun secret en clair dans Git (vérifié par la CI).

---

## ⏭️ En cours — Onboarding Max & Jules

Objectif : donner à Max et Jules un accès **administrateur** complet.

Procédure (détail dans `onboarding/PROCEDURE_ONBOARDING.md`) :
1. Ils génèrent leurs clés (WireGuard, SSH, age) → envoient les **publiques**.
2. Comptes GitLab → `terraform-gitlab/users.tf` → `terraform apply`.
3. Accès VPN → `ansible/wireguard.yml` (plage admin `10.0.0.x`) → `wireguard.yml`.
4. Accès SSH VM → `ansible/group_vars/all.yml` → `harden.yml`.
5. Accès secrets → `.sops.yaml` → `sops updatekeys`.

---

## ⬜ À venir — Services métier

**Répartition prévue :**
- **Max → ELK** (Elasticsearch + Logstash + Kibana), PROD `10.2.0.1`.
  ⚠️ Sécuriser l'entrée 5044 (TLS + auth, anti-injection de logs).
- **Jules → App web** (Web-Back + Postgres), PROD `10.2.0.3`, et Web-Front sur edge.
- **Ensuite, en commun** : Shield (image + Filebeat + nftables), IA (`10.3.0.2`).

Chaque service : disque de données si stateful, stack Docker Compose versionnée,
secrets dans SOPS, flux validés contre la table de flux, fiche dans `services/`.

---

## ⬜ Reporté (déclenchement quand le besoin est réel)

### DNS & TLS (P6)
- Acheter le domaine (`tezcat-app.fr`), Cloudflare recommandé (API DNS-01).
- DynDNS (IP Livebox dynamique).
- Certbot DNS-01 → vrai certificat GitLab (remplace l'auto-signé).
- Fait disparaître tous les contournements `sslVerify=false`.

### Sauvegardes (P8)
- restic : volumes de données (GitLab, ELK, Postgres) + dépôts Git.
- Timer systemd + **test de restauration réel**.

### CI de déploiement + backend d'état Terraform
- Aujourd'hui : `terraform apply` lancé à la main depuis un poste (suffisant en solo).
- Deviendra nécessaire quand plusieurs personnes/la CI déploieront → migrer l'état
  vers le backend GitLab (verrouillage, état partagé) puis pipeline plan/apply.
- **Déclencheur : la collaboration réelle sur l'infra** (pas avant).

### Finitions
- Épingler la version de l'image GitLab (actuellement `:latest`).
- Rotation des logs Docker (rotation configurée sur le Runner, à généraliser).
- Rebuild « en une commande » documenté (voir `DEPLOIEMENT.md`).
- Politique de rotation des secrets, veille MAJ images (Renovate/Diun).

---

## Leçons apprises (référence)

- **Routage asymétrique DMZ/DMZCLIENT** : la VM WireGuard touche ces zones sans
  passer par le firewall → route retour sur les VM concernées (préserve les IP
  sources pour le filtrage), jamais de masquerade (casse le filtrage par profil).
- **`ip route add` non idempotent** → toujours `ip route replace`.
- **Debian 13 a supprimé `apt-key`** → `deb822_repository`.
- **Ping inter-zones non autorisé par design** → tester avec `nc -zv <ip> <port>`.
- **Clés privées** : générées sur l'hôte cible, jamais dans Git ni un terminal
  partagé. Clés publiques : versionnables sans risque.
- **`terraform destroy` en VPN = danger** (détruit la VM wireguard → coupe l'accès).
  Piloter les opérations destructives depuis pve01.
- **Images d'appli sur petit disque système** → prévoir un disque de données dédié
  et la rotation des logs Docker (GitLab a saturé un `sda` de 8 Go).
