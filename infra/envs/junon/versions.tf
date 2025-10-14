terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox    = { source = "bpg/proxmox", version = "= 0.85.0" } # old 0.83.2
    talos      = { source = "siderolabs/talos", version = "= 0.9.0" } # old 0.9.0-alpha.0
    kubernetes = { source = "hashicorp/kubernetes", version = "= 2.38.0" }
    helm       = { source = "hashicorp/helm", version = "= 3.0.2" }
    local      = { source = "hashicorp/local", version = "~> 2.5.3" }
    time       = { source = "hashicorp/time", version = "~> 0.13.1" }
    sops       = { source = "carlpett/sops", version = "~> 1.3.0" }
  }
}