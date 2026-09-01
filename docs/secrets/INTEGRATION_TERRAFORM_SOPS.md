# Intégration du provider carlpett/sops dans Terraform

> Permet à Terraform de lire directement les secrets chiffrés SOPS, sans
> déchiffrement manuel. La CI (et toi en local) n'a besoin que de la clé age.

---

## 1. Déclarer le provider

Dans `provider.tf` (des dossiers `terraform/` ET `terraform-gitlab/`) :

```hcl
terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1"   # vérifier la dernière sur registry.terraform.io/providers/carlpett/sops
    }
    # ... tes autres providers (bpg/proxmox, gitlabhq/gitlab) ...
  }
}

provider "sops" {}
```

---

## 2. Lire le fichier chiffré

Dans un fichier `secrets.tf` (par dossier) :

```hcl
# terraform/secrets.tf
data "sops_file" "secrets" {
  source_file = "${path.module}/../secrets/proxmox.yaml"
}
```

Le provider déchiffre automatiquement en mémoire (jamais sur disque) en utilisant
la clé age présente sur la machine.

---

## 3. Utiliser les valeurs

Remplace tes `var.pve_api_token` par la donnée déchiffrée :

```hcl
# AVANT (variable depuis tfvars) :
#   token = var.pve_api_token

# APRÈS (depuis SOPS) :
provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = data.sops_file.secrets.data["pve_api_token"]
  insecure  = true
}
```

Pour `terraform-gitlab/` :
```hcl
data "sops_file" "secrets" {
  source_file = "${path.module}/../secrets/gitlab.yaml"
}

provider "gitlab" {
  base_url = var.gitlab_url
  token    = data.sops_file.secrets.data["gitlab_token"]
  insecure = true
}

# et pour le mot de passe initial des users :
#   password = data.sops_file.secrets.data["initial_password"]
```

---

## 4. Où vit la clé age (pour que Terraform déchiffre)

Terraform/SOPS cherche la clé privée age via la variable d'environnement
`SOPS_AGE_KEY_FILE` ou l'emplacement par défaut `~/.config/sops/age/keys.txt`.

**En local :** rien à faire, ta clé est déjà à `~/.config/sops/age/keys.txt`.

**En CI :** la clé privée du Runner est injectée via une variable GitLab (voir le
guide CI). Le pipeline exporte :
```bash
export SOPS_AGE_KEY_FILE="$RUNNER_AGE_KEY"   # variable CI de type File
```

---

## 5. Ce qui disparaît

- Plus de `terraform.tfvars` avec les secrets (le fichier peut être supprimé,
  ou ne garder que les variables non sensibles comme `pve_endpoint`).
- Plus de déchiffrement manuel avant chaque run.
- Les secrets vivent chiffrés dans Git, lus à la volée par Terraform.

> ⚠️ Garde `pve_endpoint`, `gitlab_url` etc. (non sensibles) dans un `terraform.tfvars`
>    normal ou en valeurs par défaut — seuls les vrais secrets passent par SOPS.
