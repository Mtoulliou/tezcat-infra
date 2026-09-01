# TEZCAT — Mise en place SOPS + age (secrets chiffrés dans Git)

> Objectif : versionner les secrets d'infrastructure dans Git, mais **chiffrés**.
> Chaque personne (et le Runner CI) a sa propre clé age. Un secret est chiffré
> pour toutes les clés autorisées → chacun déchiffre avec la sienne.

---

## Concepts en 30 secondes

- **age** : outil de chiffrement. Une paire de clés (publique/privée) par personne.
  - Clé **publique** (`age1...`) : sert à chiffrer. Se partage, va dans Git.
  - Clé **privée** (`AGE-SECRET-KEY-...`) : sert à déchiffrer. **Ne quitte jamais
    la machine de son propriétaire.** Secours dans Bitwarden.
- **SOPS** : utilise age pour chiffrer **uniquement les valeurs** d'un fichier YAML/JSON
  (les clés restent lisibles → on voit quels secrets existent, pas leur contenu).
- **`.sops.yaml`** : fichier de config (versionné) qui dit "tel fichier est chiffré
  pour telles clés publiques".

---

## Étape 1 — Installer les outils (chaque personne, sur son poste)

**Debian/Ubuntu :**
```bash
# age
sudo apt update && sudo apt install -y age

# sops (via le binaire officiel — vérifier la dernière version sur github.com/getsops/sops/releases)
SOPS_VERSION="v3.9.0"
curl -LO "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
sudo mv "sops-${SOPS_VERSION}.linux.amd64" /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
sops --version
```

---

## Étape 2 — Générer sa clé age (chaque personne)

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

La commande affiche la **clé publique** (`# public key: age1xxxx...`).
Le fichier `keys.txt` contient la **clé privée**.

```bash
chmod 600 ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt | grep "public key"   # ta clé PUBLIQUE à transmettre
```

> 🔑 **Sauvegarde `keys.txt` dans Bitwarden.** Si tu la perds, tu ne peux plus
>    déchiffrer aucun secret (il faudra qu'un autre détenteur re-chiffre pour ta
>    nouvelle clé).
> 🔑 **Transmets uniquement la clé PUBLIQUE** (`age1...`) à Matteo.

---

## Étape 3 — La clé du Runner CI (Matteo, une fois)

Le Runner doit pouvoir déchiffrer les secrets pendant les pipelines. On lui génère
sa propre clé age :
```bash
age-keygen -o runner-age.txt
cat runner-age.txt
```
- La clé **privée** ira dans une **variable CI/CD GitLab** (type File, masquée) —
  voir le guide CI. Ne PAS la committer.
- La clé **publique** va dans `.sops.yaml` comme les autres.

---

## Étape 4 — Le fichier .sops.yaml (Matteo, versionné)

À la racine du dépôt `infra`. Il déclare quelles clés peuvent déchiffrer quoi.

```yaml
creation_rules:
  # Tous les fichiers *.enc.yaml et secrets/*.yaml sont chiffrés pour ces clés
  - path_regex: (\.enc\.yaml|secrets/.*\.yaml)$
    key_groups:
      - age:
          - age1MATTEO_PUBLIC_KEY_ICI    # Matteo
          - age1MAXIME_PUBLIC_KEY_ICI    # Maxime
          - age1JULES_PUBLIC_KEY_ICI     # Jules
          - age1RUNNER_PUBLIC_KEY_ICI    # Runner CI
```

> Ajouter une personne = ajouter sa clé publique ici, puis re-chiffrer les secrets
> existants (voir "Gérer les accès" plus bas).

---

## Étape 5 — Chiffrer les secrets existants

Pour chaque secret, on crée un fichier YAML et on le chiffre avec SOPS.

**Exemple — token Proxmox :**
```bash
# créer le fichier en clair (temporaire)
cat > secrets/proxmox.yaml <<'YAML'
pve_api_token: "terraform@pve!terraform-token=xxxxxxxx"
YAML

# le chiffrer EN PLACE (le contenu devient illisible, mais versionnable)
sops --encrypt --in-place secrets/proxmox.yaml
```
Le fichier peut maintenant être committé : les valeurs sont chiffrées.

**Éditer un secret plus tard :**
```bash
sops secrets/proxmox.yaml    # ouvre en clair dans ton éditeur, re-chiffre à la sauvegarde
```

**Lire une valeur (ex. pour Terraform) :**
```bash
sops --decrypt secrets/proxmox.yaml
```

---

## Secrets à migrer (liste TEZCAT)

| Fichier SOPS | Contenu | Remplace |
|--------------|---------|----------|
| `secrets/proxmox.yaml` | `pve_api_token` | `terraform/terraform.tfvars` |
| `secrets/gitlab.yaml` | `gitlab_token`, `initial_password` | `terraform-gitlab/terraform.tfvars` |
| `secrets/services.yaml` | (à venir) mots de passe Postgres, ELK... | futurs `.env` |

> Le token du Runner (usage unique à l'enregistrement) n'est pas migré — voir
> l'analyse dans les notes de projet.
> La clé privée WireGuard serveur reste générée sur l'hôte (pas dans SOPS).

---

## Utiliser un secret SOPS avec Terraform

Deux approches :

**A — déchiffrer à la volée avant le run :**
```bash
sops --decrypt secrets/proxmox.yaml > terraform/secrets.auto.tfvars   # (gitignored !)
cd terraform && terraform apply
rm terraform/secrets.auto.tfvars                                        # nettoyer après
```

**B — provider SOPS Terraform** (plus élégant, à voir plus tard) :
`carlpett/sops` permet de lire directement un fichier chiffré dans le `.tf`.

> ⚠️ Le fichier déchiffré temporaire (`secrets.auto.tfvars`) DOIT être dans
>    `.gitignore` — ne jamais committer la version en clair.

---

## Gérer les accès (ajout / retrait d'une personne)

**Ajouter Maxime :**
1. Maxime génère sa clé age, envoie sa clé PUBLIQUE.
2. Ajouter sa clé publique dans `.sops.yaml`.
3. Re-chiffrer tous les secrets pour inclure sa clé :
   ```bash
   find secrets/ -name '*.yaml' -exec sops updatekeys -y {} \;
   ```
4. Commit → Maxime peut désormais déchiffrer.

**Retirer quelqu'un :**
1. Supprimer sa clé publique de `.sops.yaml`.
2. `find secrets/ -name '*.yaml' -exec sops updatekeys -y {} \;`
3. Commit → il ne peut plus déchiffrer les nouvelles versions.
4. 🔴 Considérer la rotation des secrets qu'il a pu déchiffrer par le passé
   (il a pu en garder une copie).

---

## .gitignore à compléter

```
# Clés age privées — JAMAIS dans Git
*age*.txt
keys.txt
# Déchiffrés temporaires
secrets.auto.tfvars
*.dec.yaml
```

> Les fichiers `secrets/*.yaml` chiffrés par SOPS, EUX, sont committés (c'est le but).
