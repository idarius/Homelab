resource "helm_release" "cilium" {
  depends_on = [null_resource.wait_apiserver]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"
  version    = local.versions.cilium_chart

  wait    = true
  atomic  = true
  timeout = 1200

  values = [yamlencode({

    kubeProxyReplacement = "true"

    ipam = { mode = "kubernetes" }
    devices = ["eth0"]

    l2announcements = {
      enabled = true
    }

    l2NeighDiscovery = {
      enabled = true
    }

    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN","KILL","NET_ADMIN","NET_RAW","IPC_LOCK","SYS_ADMIN",
          "SYS_RESOURCE","DAC_OVERRIDE","FOWNER","SETGID","SETUID"
        ]
        cleanCiliumState = [
          "NET_ADMIN","SYS_ADMIN","SYS_RESOURCE"
        ]
      }
    }

    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }

    hubble = {
      enabled = true
      relay   = { enabled = true }
      ui      = { enabled = true }
    }

    operator = { replicas = 1 }

    k8sServiceHost = var.control_plane_nodes[0].ip
    k8sServicePort = 6443

  })]
}



resource "null_resource" "wait_nodes_ready" {
  depends_on = [helm_release.cilium]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = { KUBECONFIG = abspath("${path.module}/kubeconfig") }

    command = <<EOT
set -euo pipefail

echo "[wait] attente création du DaemonSet cilium..."
until kubectl -n kube-system get ds cilium >/dev/null 2>&1; do
  echo "[wait] cilium ds not created yet..."
  sleep 3
done

echo "[wait] rollout Cilium (DaemonSet)..."
kubectl -n kube-system rollout status ds/cilium --timeout=15m

echo "[wait] attente création du Deployment cilium-operator..."
until kubectl -n kube-system get deploy cilium-operator >/dev/null 2>&1; do
  echo "[wait] cilium-operator not created yet..."
  sleep 3
done

echo "[wait] rollout cilium-operator..."
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=10m

echo "[wait] attente Node Ready..."
kubectl wait node --all --for=condition=Ready --timeout=10m
EOT
  }
}

resource "null_resource" "cilium_lb_pool" {
  depends_on = [null_resource.wait_nodes_ready]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = { KUBECONFIG = abspath("${path.module}/kubeconfig") }
    command = <<EOT
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: homelab-pool
spec:
  blocks:
    - cidr: 192.168.0.240/29
EOF
EOT
  }
}

resource "null_resource" "cilium_lb_policy" {
  depends_on = [null_resource.cilium_lb_pool]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = { KUBECONFIG = abspath("${path.module}/kubeconfig") }
    command = <<EOT
cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: homelab-l2policy
spec:
  serviceSelector:
    matchLabels: {}
  interfaces:
    - eth0
  loadBalancerIPs: true
EOF
EOT
  }
}