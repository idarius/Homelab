resource "proxmox_virtual_environment_vm" "control_plane" {
  count         = length(var.control_plane_nodes)
  name          = var.control_plane_nodes[count.index].name
  description   = "Talos Kubernetes control plane node"
  node_name     = local.secrets.proxmox.node
  vm_id         = var.control_plane_nodes[count.index].id
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = local.secrets.proxmox.storage_pool
    interface    = "scsi0"
    size         = 30
    ssd          = true
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_file.talos_iso.id
  }

  network_device {
    bridge      = local.secrets.proxmox.bridge
    model       = "virtio"
    firewall    = false
    mac_address = local.secrets.proxmox.control_plane_mac
  }

  started = true
}