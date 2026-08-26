# ==========================================================================
#  UTILISATEURS
#  ⚠️ reset_password = true → GitLab envoie un mail de définition de mot de
#     passe. Sans serveur mail configuré, préférer password + force_password_change
#     (voir la note en bas) ou créer les users à la main dans l'UI.
# ==========================================================================

locals {
  # Administrateurs : Owner du groupe tezcat (droits complets sur tous les projets)
  admins = {
    matteo = {
      name     = "Matteo"
      email    = "matteo.meze@gmail.com"
      is_admin = true # admin de l'instance GitLab
    }
    maxime = {
      name     = "Maxime"
      email    = "maximearroyo.pro@gmail.com"
      is_admin = true
    }
    jules = {
      name     = "Jules"
      email    = "6moricejules6@gmail.com"
      is_admin = true
    }
  }

  # Développeurs : accès developer sur le groupe (à compléter plus tard)
  devs = {
    # exemple :
    # "prenom.nom" = { name = "Prénom Nom", email = "prenom@tezcat.local" }
  }
}

# ---------------------------- ADMINS -------------------------------------
resource "gitlab_user" "admins" {
  for_each = local.admins

  name             = each.value.name
  username         = each.key
  email            = each.value.email
  is_admin         = each.value.is_admin
  password = data.sops_file.secrets.data["initial_password"]  
  projects_limit   = 100
  can_create_group = true
  state            = "active"
}

resource "gitlab_group_membership" "admins" {
  for_each = local.admins

  group_id     = gitlab_group.tezcat.id
  user_id      = gitlab_user.admins[each.key].id
  access_level = "owner" # droits complets sur le groupe et ses projets
}

# ----------------------------- DEVS --------------------------------------
resource "gitlab_user" "devs" {
  for_each = local.devs

  name             = each.value.name
  username         = each.key
  email            = each.value.email
  is_admin         = false
  password = data.sops_file.secrets.data["initial_password"]  
  projects_limit   = 20
  can_create_group = false
  state            = "active"
}

resource "gitlab_group_membership" "devs" {
  for_each = local.devs

  group_id     = gitlab_group.tezcat.id
  user_id      = gitlab_user.devs[each.key].id
  access_level = "developer" # push sur les branches non protégées, pas de force-push sur main
}
