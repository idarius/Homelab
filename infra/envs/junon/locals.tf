locals {
  versions = {
    talos         = "v1.11.1"
    kubernetes    = "v1.34.1"
    cilium_chart  = "1.16.5"
    argocd_chart  = "7.1.0"
    traefik_chart = "37.1.2"
  }
  cluster_name      = local.secrets.cluster.name
  control_plane_vip = local.secrets.cluster.control_plane_vip
  gateway           = local.secrets.cluster.gateway
  pod_subnet        = "10.244.0.0/16"
  svc_subnet        = "10.96.0.0/12"
}
