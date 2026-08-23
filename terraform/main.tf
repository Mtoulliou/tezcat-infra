resource "proxmox_virtual_environment_vm" "firewall" {
  name      = "firewall"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 1
  }
  memory {
    dedicated = 1024
  }

  startup {
    order = 1
  }

  network_device {
    bridge = "vmbr0"
  } # net0 - domestique
  network_device {
    bridge = "vmbr1"
  } # net1 - DMZ
  network_device {
    bridge = "vmbr2"
  } # net2 - PROD
  network_device {
    bridge = "vmbr3"
  } # net3 - DMZCLIENT

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "192.168.1.27/24"
        gateway = "192.168.1.1"
      }
    }
    ip_config {
      ipv4 {
        address = "10.1.0.254/24"
      }
    }
    ip_config {
      ipv4 {
        address = "10.2.0.254/24"
      }
    }
    ip_config {
      ipv4 {
        address = "10.3.0.254/24"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

resource "proxmox_virtual_environment_vm" "wireguard" {
  name      = "wireguard"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 1
  }
  memory {
    dedicated = 1024
  }

  startup {
    order = 2
  }

  network_device {
    bridge = "vmbr1"
  } # net0 - DMZ
  network_device {
    bridge = "vmbr3"
  } # net1 - DMZCLIENT

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "10.1.0.3/24"
        gateway = "10.1.0.254"
      }
    }
    ip_config {
      ipv4 {
        address = "10.3.0.1/24"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

resource "proxmox_virtual_environment_vm" "shield_test" {
  name      = "shield-test"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  } # net0 - domestique
  network_device {
    bridge = "vmbr4"
  } # net1 - LAN client simulé

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "192.168.1.28/24"
        gateway = "192.168.1.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.0.254/24"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

# --- EDGE (Nginx + Certbot + Web-Front) — DMZ ---
resource "proxmox_virtual_environment_vm" "edge" {
  name      = "edge"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr1"
  }

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "10.1.0.1/24"
        gateway = "10.1.0.254"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

# --- GITLAB (+ Runner) — PROD ---
resource "proxmox_virtual_environment_vm" "gitlab" {
  name      = "gitlab"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 4
  }
  memory {
    dedicated = 7168
  }

  network_device {
    bridge = "vmbr2"
  }

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  disk {
    datastore_id = "hdd-mirror"
    interface    = "scsi1"
    size         = 50
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "10.2.0.2/24"
        gateway = "10.2.0.254"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

# --- ELK — PROD ---
resource "proxmox_virtual_environment_vm" "elk" {
  name      = "elk"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 4
  }
  memory {
    dedicated = 4096
  }

  network_device {
    bridge = "vmbr2"
  }

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "10.2.0.1/24"
        gateway = "10.2.0.254"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

# --- APP (Web-Back + Postgres) — PROD ---
resource "proxmox_virtual_environment_vm" "app" {
  name      = "app"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr2"
  }

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "10.2.0.3/24"
        gateway = "10.2.0.254"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}

# --- IA — DMZCLIENT ---
resource "proxmox_virtual_environment_vm" "ia" {
  name      = "ia"
  node_name = local.node

  clone {
    vm_id = local.template
    full  = true
  }

  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr3"
  }

  disk {
    datastore_id = "local"     # ton SSD (type Répertoire)
    interface    = "scsi0"
  }

  initialization {
    datastore_id = "local"     # ← AJOUTER cette ligne en haut du bloc
    ip_config {
      ipv4 {
        address = "10.3.0.2/24"
        gateway = "10.3.0.254"
      }
    }
    user_account {
      username = "tezcatadmin"
      keys     = [local.ssh_key]
    }
  }

  agent {
    enabled = true
  }
}
