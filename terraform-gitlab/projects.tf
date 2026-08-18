# ==========================================================================
#  PROJETS (dépôts) — tous dans le groupe tezcat
# ==========================================================================

locals {
  projects = {
    infra = {
      description = "Infrastructure as code — Terraform, Ansible, firewall, VPN"
    }
    ai = {
      description = "Moteur d'analyse et de décision (arbres de décision, LLM)"
    }
    app = {
      description = "Application web — front, back, API"
    }
    shield = {
      description = "Appliance Shield — image, Filebeat, nftables"
    }
  }
}

resource "gitlab_project" "tezcat" {
  for_each = local.projects

  name             = each.key
  path             = each.key
  namespace_id     = gitlab_group.tezcat.id
  description      = each.value.description
  visibility_level = "private"

  # Hygiène de dépôt
  default_branch                   = "main"
  initialize_with_readme           = false # false → permet un premier push depuis un dépôt local existant
  shared_runners_enabled           = true
  only_allow_merge_if_pipeline_succeeds = false # à passer à true quand la CI sera en place
  remove_source_branch_after_merge = true
  squash_option                    = "default_off"
}

# ----------------- Protection de la branche main -------------------------
resource "gitlab_branch_protection" "main" {
  for_each = local.projects

  project            = gitlab_project.tezcat[each.key].id
  branch             = "main"
  push_access_level  = "maintainer" # les devs passent par merge request
  merge_access_level = "developer"
  allow_force_push   = false

  # ⚠️ La branche doit EXISTER pour être protégée.
  # Au premier apply, si le dépôt est vide, commenter cette ressource,
  # pousser le code, puis décommenter et relancer.
  depends_on = [gitlab_project.tezcat]
}
