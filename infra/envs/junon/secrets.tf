data "sops_file" "cluster" { source_file = "${path.module}/tfvars/cluster.sops.yaml" }
locals { secrets = yamldecode(data.sops_file.cluster.raw) }
