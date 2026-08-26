variable "pve_endpoint" {
  type        = string
  description = "URL de l'API Proxmox"
}

locals {
  ssh_key  = trimspace(file(pathexpand("~/.ssh/tezcat_ed25519.pub")))
  template = 9000
  node     = "pve01"
}

