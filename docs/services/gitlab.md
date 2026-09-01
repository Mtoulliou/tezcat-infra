# Service — GitLab (+ Runner)

## Rôle
Backbone de développement : dépôts Git, gestion des accès (users/groupes/projets),
CI/CD via le Runner. Configuré entièrement as-code.

## Emplacement
| | |
|---|---|
| VM | gitlab (Terraform id 100) |
| Zone | PROD |
| IP | 10.2.0.2 |
| Ports | 443 (HTTPS web), 2222 (git SSH — 22 pris par l'hôte) |
| Responsable | Matteo |

## Dépendances
- Firewall (accès VPN 22/443/2222), Docker (docker.yml).
- Disque de données dédié (`sdb`, 50 Go sur miroir HDD) monté sur `/srv/gitlab`.
- Disque système agrandi à 30 Go (l'image GitLab + Docker saturait 8 Go).

## Déploiement
```bash
ansible-playbook gitlab.yml                              # disque + stack
ansible-playbook runner.yml -e "runner_token=glrt-..."   # Runner
```
- Fichiers : `ansible/gitlab.yml`, `ansible/runner.yml`.
- Config as-code des users/groupes/projets : `terraform-gitlab/`.
- Certificat auto-signé (en attendant DNS-01). Volumes sur `/srv/gitlab`.
- Runner : executor Docker, concurrent=1, limite 1g/job, config sur
  `/srv/gitlab-runner`, certificat GitLab monté pour la confiance TLS.

## Configuration
- Stack : `docker-compose.yml` généré par le playbook (external_url, ports, volumes).
- Users/groupes/projets : Terraform (`gitlabhq/gitlab`), groupe `tezcat` + 4 projets.
- ⚠️ Image en `:latest` — à épingler.

## Secrets (SOPS)
- `secrets/gitlab.yaml` : `gitlab_token` (API, pour Terraform), `initial_password`
  (mot de passe temporaire des comptes).
- Token du Runner : passé en `--extra-vars` à l'enregistrement (usage unique).

## Flux réseau
| Source | → Destination | Port | Rôle |
|--------|---------------|------|------|
| VPN admin | gitlab | 22,443,2222 | admin + git |
| VPN dev | gitlab | 443,2222 | git |
| Runner | gitlab (api) | 443 | CI |

## Accès
Web : `https://10.2.0.2` (VPN, accepter le certificat auto-signé).
Git SSH : `git clone ssh://git@10.2.0.2:2222/tezcat/<projet>.git`.
Git HTTPS : ajouter `-c http.sslVerify=false` (auto-signé).

## Dépannage
| Symptôme | Piste |
|----------|-------|
| Web inaccessible en VPN | conteneur up (`docker ps`) · port 443 dans nftables · certificat navigateur |
| Disque plein | `df -h` · logs Docker non tournés · `docker system prune` |
| Runner ne prend pas de job | pastille verte dans Admin→CI/CD→Runners · certificat TLS |
| `terraform init` TLS timeout | tunnel VPN · GitLab arrêté |
