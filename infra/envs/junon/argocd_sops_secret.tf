resource "null_resource" "ensure_ns_argocd" {
  depends_on = [null_resource.cilium_lb_policy, local_file.kubeconfig]

  provisioner "local-exec" {
    interpreter = ["/bin/bash","-c"]
    environment = { KUBECONFIG = abspath("${path.module}/kubeconfig") }
    command = <<-EOT
      set -euo pipefail
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }
}

resource "null_resource" "apply_argocd_sops_age_secret" {
  depends_on = [null_resource.ensure_ns_argocd]

  provisioner "local-exec" {
    interpreter = ["/bin/bash","-c"]
    environment = {
      KUBECONFIG = abspath("${path.module}/kubeconfig")
      SOPS_KEYS  = local.secrets.sops_age.keys_txt
    }
    command = <<-EOT
      set -euo pipefail

      # base64 oneline (fallback si -w0 indispo)
      if B64=$(printf "%s" "$SOPS_KEYS" | base64 -w0 2>/dev/null); then
        :
      else
        B64=$(printf "%s" "$SOPS_KEYS" | base64 | tr -d '\\n')
      fi

      cat <<YAML | kubectl apply -f -
      apiVersion: v1
      kind: Secret
      metadata:
        name: argocd-sops-age
        namespace: argocd
      type: Opaque
      data:
        keys.txt: $${B64}
      YAML
    EOT
  }
}