data "sops_file" "secrets" {
  source_file = "${path.module}/../secrets/proxmox.yaml"
}