############################################
# Helm Argo CD (avec CRDs + KSOPS/SOPS)
############################################
resource "helm_release" "argocd" {
  # On attend que le cluster soit vraiment opérationnel (réseau/Cilium OK)
  depends_on = [
    null_resource.wait_nodes_ready,
    null_resource.apply_argocd_sops_age_secret,
    null_resource.ensure_ns_argocd
  ]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = local.versions.argocd_chart

  namespace        = "argocd"
  create_namespace = false

  wait    = true
  atomic  = true
  timeout = 1200

  values = [
    yamlencode({
      installCRDs = true

      server = {
        service   = { type = "LoadBalancer" }
        extraArgs = ["--insecure"]
      }

      configs = {
        params = {
          "application.namespaces" = "argocd"
          "server.insecure"        = "true"
        }
        cm = {
          # Alpha plugins + chargement permissif pour les chemins relatifs (../) si tu en utilises
          "kustomize.buildOptions" = "--enable-alpha-plugins --load-restrictor=LoadRestrictionsNone"
          # Optionnel : URL publique (utile pour cookies/redirect). Mets ton IP/DNS si besoin.
          url = "http://192.168.0.240"
        }
      }

      repoServer = {
        env = [
          { name = "SOPS_AGE_KEY_FILE",     value = "/home/argocd/.config/sops/age/keys.txt" },
          { name = "PATH",                  value = "/usr/local/bin:/usr/bin:/bin:/custom-tools" },
          { name = "KUSTOMIZE_PLUGIN_HOME", value = "/home/argocd/.config/kustomize/plugin" },
          { name = "KUSTOMIZE_ENABLE_ALPHA_PLUGINS", value = "true" }
        ]
        volumes = [
          { name = "sops-age",          secret   = { secretName = "argocd-sops-age" } },
          { name = "custom-tools",      emptyDir = {} },
          { name = "kustomize-plugins", emptyDir = {} }
        ]
        volumeMounts = [
          { name = "sops-age",          mountPath = "/home/argocd/.config/sops/age" },
          { name = "custom-tools",      mountPath = "/custom-tools" },
          { name = "kustomize-plugins", mountPath = "/home/argocd/.config/kustomize/plugin" }
        ]
        initContainers = [
          {
            name    = "install-sops-ksops"
            image   = "alpine:3.20"
            command = ["/bin/sh","-c"]
            volumeMounts = [
              { name = "custom-tools",      mountPath = "/custom-tools" },
              { name = "kustomize-plugins", mountPath = "/home/argocd/.config/kustomize/plugin" }
            ]
            args    = [<<-SH
set -eux
apk add --no-cache ca-certificates curl tar

# --- SOPS (dernière version stable) ---
curl -fsSL -o /custom-tools/sops https://github.com/getsops/sops/releases/download/v3.9.3/sops-v3.9.3.linux.amd64
chmod +x /custom-tools/sops

# --- KSOPS (latest stable) ---
ARCH=$$(uname -m)
case "$$ARCH" in
  x86_64)           KSOPS_ARCH=x86_64 ;;
  aarch64|arm64)    KSOPS_ARCH=arm64 ;;
  *)                KSOPS_ARCH=x86_64 ;;
esac

# Utiliser la version latest qui est toujours disponible
URL="https://github.com/viaduct-ai/kustomize-sops/releases/latest/download/ksops_latest_Linux_$${KSOPS_ARCH}.tar.gz"
echo "[init] Téléchargement KSOPS depuis: $$URL"
curl -fsSL -o /tmp/ksops.tar.gz "$$URL"

tar --no-same-owner -xzf /tmp/ksops.tar.gz -C /custom-tools
mkdir -p /home/argocd/.config/kustomize/plugin/viaduct.ai/v1/ksops
install -m 0755 /custom-tools/ksops /home/argocd/.config/kustomize/plugin/viaduct.ai/v1/ksops/ksops

echo "[init] SOPS et KSOPS installés avec succès"
ls -la /custom-tools/
ls -la /home/argocd/.config/kustomize/plugin/viaduct.ai/v1/ksops/
SH
            ]
            securityContext = {
              allowPrivilegeEscalation = false
              runAsNonRoot             = false
              runAsUser                = 0
              seccompProfile           = { type = "RuntimeDefault" }
              capabilities             = { drop = ["ALL"] }
            }
          }
        ]
      }
    })
  ]
}

############################################
# Attendre que les CRDs ArgoCD soient dispos (anti-race)
############################################
resource "null_resource" "wait_argocd_crds" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = { KUBECONFIG = abspath("${path.module}/kubeconfig") }
    command     = <<EOT
set -euo pipefail
echo "[wait] attente CRDs ArgoCD..."
for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
  until kubectl get crd "$crd" >/dev/null 2>&1; do
    echo "[wait] $crd not ready yet..."
    sleep 2
  done
done
echo "[wait] CRDs ArgoCD OK."
EOT
  }
}

############################################
# App-of-apps (root) via kubectl
############################################
resource "null_resource" "apply_platform_root_app" {
  depends_on = [
    null_resource.wait_argocd_crds,
    helm_release.argocd,
    local_file.kubeconfig
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = abspath("${path.module}/kubeconfig")
    }
    command = <<-EOT
      set -euo pipefail
      kubectl apply -f "${path.module}/../../../clusters/junon/root/app-root.yaml"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = abspath("${path.module}/kubeconfig")
    }
    command = <<-EOT
      set -euo pipefail
      kubectl delete -f "${path.module}/../../../clusters/junon/root/app-root.yaml" --ignore-not-found=true
    EOT
  }
}

############################################
# ApplicationSet (apps) via kubectl
############################################
resource "null_resource" "apply_apps_applicationset" {
  depends_on = [
    null_resource.wait_argocd_crds,
    helm_release.argocd,
    local_file.kubeconfig,
    null_resource.apply_platform_root_app
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = abspath("${path.module}/kubeconfig")
    }
    command = <<-EOT
      set -euo pipefail
      kubectl apply -f "${path.module}/../../../clusters/junon/apps/applicationset.yaml"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = abspath("${path.module}/kubeconfig")
    }
    command = <<-EOT
      set -euo pipefail
      kubectl delete -f "${path.module}/../../../clusters/junon/apps/applicationset.yaml" --ignore-not-found=true
    EOT
  }
}





############################################
# Afficher l'accès ArgoCD en fin d'apply
############################################
resource "null_resource" "show_argocd_access" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    interpreter = ["/bin/bash","-c"]
    environment = { KUBECONFIG = abspath("${path.module}/kubeconfig") }
    command = <<-EOT
      set -euo pipefail
      IP=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
      PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
      echo
      echo "[ArgoCD] http://$IP/"
      echo "[ArgoCD] user: admin"
      echo "[ArgoCD] pass: $PW"
      echo
      kubectl -n argocd get svc argocd-server -o wide
    EOT
  }
}
