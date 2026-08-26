variable "pve_endpoint" {
  type        = string
  description = "URL de l'API Proxmox"
}

variable "ssh_public_key" {
  type        = string
  description = "Clé publique SSH injectée dans les VM (cloud-init)"
}

locals {
  ssh_key  = trimspace(var.ssh_public_key)
  template = 9000
  node     = "pve01"
}

