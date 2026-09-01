# Service — Firewall

## Rôle
Nœud central de routage et de filtrage. Route entre les 5 zones, applique le NAT
vers Internet, redirige les entrées (DNAT), et filtre selon la table de flux
(policy drop par défaut). C'est la pièce dont dépend toute la connectivité interne.

## Emplacement
| | |
|---|---|
| VM | firewall (Terraform id 102) |
| Zone | toutes (multi-pattes) |
| IP | eth0 192.168.1.27 (domestique) · eth1 10.1.0.254 (DMZ) · eth2 10.2.0.254 (PROD) · eth3 10.3.0.254 (DMZCLIENT) |
| Responsable | Matteo |

## Dépendances
- **Prérequis de tout le reste** : sans lui, aucune zone interne n'est joignable.
- Démarre en premier au boot (`startup order = 1`).
- La box (192.168.1.1) comme passerelle vers Internet.

## Déploiement
```bash
ansible-playbook firewall.yml
```
- Fichiers : `ansible/firewall.yml`, `ansible/firewall/nftables.conf` (versionné).
- Installe nftables, active l'IP forwarding (persistant), déploie les règles
  (avec `validate: nft -c -f` avant écriture), pose la route retour VPN via un
  service systemd idempotent.

## Configuration
- Règles dans `nftables.conf` (versionné). Toute modif : éditer le fichier →
  `ansible-playbook firewall.yml` (jamais à la main sur la VM).
- IP forwarding : `/etc/sysctl.d/99-tezcat-fw.conf`.
- Route retour VPN : `tezcat-route-vpn.service` (`ip route replace 10.0.0.0/16 via 10.1.0.3`).

## Secrets
Aucun (pas de secret propre au firewall).

## Flux réseau (résumé)
| Source | → Destination | Port | Rôle |
|--------|---------------|------|------|
| Internet | edge (10.1.0.1) | 80,443 | DNAT web |
| Internet | wireguard (10.1.0.3) | 51820/udp | DNAT VPN |
| VPN admin (10.0.0.x) | GitLab | 22,443,2222 | admin |
| VPN admin | Kibana / Proxmox | 5601 / 8006 | admin |
| VPN dev (10.0.1.x) | GitLab | 22,443 | dev |
| VPN shield (10.0.2.x) | ELK | 5044 | logs |
| edge | app | 8000 | API |
| IA | ELK | 9200 | lecture |
| zones internes | Internet | 53,80,443 | MAJ / egress (masqueradé) |

## Accès
SSH via VPN admin ou réseau domestique : `ssh tezcatadmin@10.1.0.254` (ou .27).
⚠️ Toujours garder la console Proxmox ouverte lors des modifs (filet anti-lockout).

## Dépannage
| Symptôme | Piste |
|----------|-------|
| Zone interne injoignable | `sysctl net.ipv4.ip_forward` (=1) · règles chargées (`nft list ruleset`) · noms d'interfaces dans nftables.conf |
| SSH firewall KO en VPN | route retour absente (`ip route show \| grep 10.0.0`) ou masquerade résiduel sur wireguard |
| Ping inter-zones échoue | **normal** (ICMP non autorisé), tester avec `nc -zv` |
