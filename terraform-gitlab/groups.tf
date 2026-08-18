# ==========================================================================
#  GROUPE PRINCIPAL — namespace qui contient tous les projets TEZCAT
# ==========================================================================
resource "gitlab_group" "tezcat" {
  name             = "tezcat"
  path             = "tezcat"
  description      = "Projets TEZCAT — Firewall as a Service"
  visibility_level = "private"

  # Bonnes pratiques de départ
  require_two_factor_authentication = false # à passer à true plus tard
  project_creation_level            = "maintainer"
  subgroup_creation_level           = "owner"
}
