variable "pve_endpoint" {
  type        = string
  description = "URL de l'API Proxmox"
}

variable "pve_api_token" {
  type        = string
  description = "Token API au format user@realm!tokenid=secret"
  sensitive   = true
}

locals {
  ssh_key  = trimspace(file(pathexpand("~/.ssh/tezcat_ed25519.pub")))
  template = 9000
  node     = "pve01"
}
