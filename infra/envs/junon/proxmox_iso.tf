resource "proxmox_virtual_environment_file" "talos_iso" {
  content_type = "iso"
  datastore_id = local.secrets.proxmox.datastore_id
  node_name    = local.secrets.proxmox.node

  source_file {
    path = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/${local.versions.talos}/nocloud-amd64.iso"
  }
}
