output "kubeconfig_path" {
  value = local_file.kubeconfig.filename
}

output "talosconfig_path" {
  value = local_file.talosconfig.filename
}

output "control_plane_ips" {
  value = [for n in var.control_plane_nodes : n.ip]
}
