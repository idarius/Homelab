provider "proxmox" {
  endpoint  = local.secrets.proxmox.api_url
  api_token = "${local.secrets.proxmox.token_id}=${local.secrets.proxmox.token_secret}"
  insecure  = true

  ssh {
    agent    = false
    username = local.secrets.proxmox.ssh_username
    password = local.secrets.proxmox.ssh_password
  }
}

provider "helm" {
  kubernetes = {
    config_path = abspath("${path.module}/kubeconfig")
  }
}

# Provider Kubernetes standard
provider "kubernetes" {
  config_path = abspath("${path.module}/kubeconfig")
}