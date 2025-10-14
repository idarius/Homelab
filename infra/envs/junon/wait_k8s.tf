resource "null_resource" "wait_apiserver" {
  depends_on = [local_file.kubeconfig]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      KUBECONFIG = abspath("${path.module}/kubeconfig")
    }

    command = <<EOT
set -euo pipefail


echo "[wait] Checking API server health..."
until kubectl get --raw="/healthz" >/dev/null 2>&1; do
  echo "[wait] apiserver not ready yet..."
  sleep 3
done
echo "[wait] apiserver is up."
EOT
  }
}
