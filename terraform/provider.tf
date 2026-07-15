terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"   # vérifie la dernière version sur le registry Terraform
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = true   # certificat auto-signé de Proxmox → toléré en R&D
}
