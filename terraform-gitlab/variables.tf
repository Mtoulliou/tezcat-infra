variable "gitlab_url" {
  type        = string
  description = "URL de l'API GitLab"
  default     = "https://10.2.0.2/api/v4"
}

variable "gitlab_token" {
  type        = string
  description = "Token API GitLab (scope: api) — créé manuellement dans l'UI"
  sensitive   = true
}

variable "initial_password" {
  type        = string
  description = "Mot de passe temporaire des comptes créés (à changer à la 1ère connexion)"
  sensitive   = true
}