# ==========================================================================
#  TEZCAT — Configuration GitLab as code
#  Projet Terraform SÉPARÉ de celui des VM (cycles de vie différents,
#  état distinct → moins risqué)
# ==========================================================================
terraform {
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 17.0" # ⚠️ vérifier la dernière version sur registry.terraform.io
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1"
    }
  }
}

provider "gitlab" {
  base_url = var.gitlab_url
  token    = data.sops_file.secrets.data["gitlab_token"]
  insecure = true # certificat auto-signé — retirer une fois le vrai cert en place (P6)
}
