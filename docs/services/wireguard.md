# Service — WireGuard (bastion VPN)

## Rôle
Point d'entrée VPN unique pour l'accès distant. Trois profils (admin / dev / shield)
avec des droits différents. Applique aussi une partie du filtrage réseau (il touche
directement les zones DMZ et DMZCLIENT).

## Emplacement
| | |
|---|---|
| VM | wireguard (Terraform id 106) |
| Zone | DMZ + DMZCLIENT |
| IP | 10.1.0.3 (DMZ) · 10.3.0.1 (DMZCLIENT) |
| Port | 51820/udp (DNAT depuis Internet via le firewall) |
| Responsable | Matteo |

## Dépendances
- Firewall (DNAT 51820 → 10.1.0.3, routage).
- Port-forward 51820/udp sur la box vers 192.168.1.27.
- Démarre en second au boot (`startup order = 2`).

## Déploiement
```bash
ansible-playbook wireguard.yml
```
- Fichiers : `ansible/wireguard.yml`.
- Clé serveur **générée sur l'hôte** (jamais dans Git), lue via slurp+no_log.
- `wg0.conf` généré depuis les variables. Pairs déclarés dans `wg_peers`.
- Filtrage FORWARD par profil (DMZ + DMZCLIENT).
- IP forwarding persistant (`/etc/sysctl.d/99-wg.conf`).

## Configuration — profils
| Profil | Plage | Accès |
|--------|-------|-------|
| Admin | 10.0.0.0/24 | tout (GitLab, Kibana, Proxmox, SSH) |
| Dev | 10.0.1.0/24 | GitLab uniquement |
| Shield | 10.0.2.0/24 | ELK 5044 uniquement |

Ajout/révocation d'un pair : voir `../runbooks/wireguard_pair.md`.
Le contrôle d'accès réel est appliqué par nftables (firewall) + FORWARD (bastion),
PAS par les AllowedIPs côté client (éditables par l'utilisateur).

## Secrets
- Clé privée serveur : sur la VM (`/etc/wireguard/`), pas dans SOPS (choix : plus
  sûr générée sur l'hôte ; si la VM est recréée, la clé change → redistribuer la
  publique aux clients).
- Clés privées clients : chez chaque client, jamais transmises.

## Flux réseau
| Source | → Destination | Port | Rôle |
|--------|---------------|------|------|
| Internet | wireguard | 51820/udp | tunnel entrant |
| clients VPN | zones internes | selon profil | via firewall |

## Accès
`sudo wg-quick up wg0` côté client (config fournie à l'onboarding). Vérif : `sudo wg show`.

## Dépannage
| Symptôme | Piste |
|----------|-------|
| Pas de handshake | port-forward box · DNAT firewall · CGNAT · tester en 4G |
| Handshake OK mais rien ne répond | route retour firewall · ip_forward sur wireguard |
| Source vue comme 10.1.0.3 | masquerade résiduel → casse le filtrage par profil, à retirer |
| `resolvconf: command not found` (client) | `apt install openresolv` ou commenter DNS= |
