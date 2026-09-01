# Service — <NOM>

> Fiche de référence. À remplir par le responsable du service et tenir à jour.

## Rôle
<Ce que fait ce service en une ou deux phrases.>

## Emplacement
| | |
|---|---|
| VM | <nom> |
| Zone | <DMZ / PROD / DMZCLIENT / ...> |
| IP | <10.x.x.x> |
| Responsable | <prénom> |

## Dépendances
- <De quoi ce service a besoin (autres services, ports, réseau).>
- <Qui dépend de lui.>

## Déploiement
```bash
# playbook / terraform à lancer
```
- Fichiers concernés : <playbook.yml, docker-compose, ...>
- Disque de données : <oui/non, chemin, taille>

## Configuration
<Où vit la config, ce qui est paramétrable, ce qui est géré en code.>

## Secrets
<Quels secrets, où (SOPS : secrets/xxx.yaml), comment injectés.>

## Flux réseau (extrait de la table de flux)
| Source | → Destination | Port | Sens |
|--------|---------------|------|------|
| | | | |

## Accès
<Comment y accéder (VPN, URL, port), avec quels droits.>

## Dépannage
| Symptôme | Piste |
|----------|-------|
| | |
