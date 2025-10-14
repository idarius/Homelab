# Secrets de cluster/machines Talos
resource "talos_machine_secrets" "this" {}

# Patch de configuration Talos pour le nœud de contrôle
# - kube-proxy désactivé (on utilisera Cilium en replacement strict)
# - allowSchedulingOnControlPlanes pour single-node
# - subnets pods/services
# - DNS/NTP/registries
locals {
  controlplane_patch = <<-EOT
machine:
  network:
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
  time:
    servers:
      - time.cloudflare.com
  install:
    disk: /dev/sda
    image: ghcr.io/siderolabs/installer:${local.versions.talos}
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://registry-1.docker.io
      ghcr.io:
        endpoints:
          - https://ghcr.io
      quay.io:
        endpoints:
          - https://quay.io
      registry.k8s.io:
        endpoints:
          - https://registry.k8s.io

cluster:
  allowSchedulingOnControlPlanes: true
  network:
    cni:
      name: none
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
  proxy:
    disabled: true
EOT
}

# Génère la configuration machine Talos (control plane)
data "talos_machine_configuration" "control_plane" {
  cluster_name       = local.secrets.cluster.name
  # IMPORTANT : endpoint = IP du nœud (pas de VIP en single node)
  cluster_endpoint   = "https://${var.control_plane_nodes[0].ip}:6443"
  machine_type       = "controlplane"
  kubernetes_version = local.versions.kubernetes
  talos_version      = local.versions.talos
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = [
    local.controlplane_patch
  ]
}

# talosconfig (client)
data "talos_client_configuration" "this" {
  cluster_name         = local.secrets.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n in var.control_plane_nodes : n.ip]
  nodes                = [for n in var.control_plane_nodes : n.ip]
}

# Applique la configuration Talos au(x) nœud(s)
resource "talos_machine_configuration_apply" "control_plane" {
  depends_on = [
    proxmox_virtual_environment_vm.control_plane
  ]

  count = length(var.control_plane_nodes)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  node                        = var.control_plane_nodes[count.index].ip
  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${var.control_plane_nodes[count.index].ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.secrets.cluster.gateway
                }
              ]
            }
          ]
          kubespan = {
            enabled = false
          }
        }
        kubelet = {
          extraArgs = {
            "node-ip" = var.control_plane_nodes[count.index].ip
          }
        }
      }
    })
  ]

}

resource "time_sleep" "wait_after_apply" {
  depends_on      = [talos_machine_configuration_apply.control_plane]
  create_duration = "30s"
}

resource "null_resource" "wait_talos_api" {
  depends_on = [time_sleep.wait_after_apply]
  provisioner "local-exec" {
    command = "talosctl --talosconfig ${path.module}/talosconfig -n ${var.control_plane_nodes[0].ip} version"
  }
}
resource "talos_machine_bootstrap" "this" {
  depends_on = [null_resource.wait_talos_api]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes[0].ip
}

# Récupère le kubeconfig
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.control_plane_nodes[0].ip
}

# Écrit les fichiers locaux
resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}

resource "local_file" "kubeconfig" {
  depends_on = [talos_cluster_kubeconfig.this]
  content    = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename   = "${path.module}/kubeconfig"
}
