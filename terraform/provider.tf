terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1" # vérifie la dernière version sur le registry Terraform
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1"       # vérifie la dernière sur registry.terraform.io
    }
    backend "http" {}
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = data.sops_file.secrets.data["pve_api_token"]  
  insecure  = true # certificat auto-signé de Proxmox → toléré en R&D
}
