# Outputs are an operator's interface, not a module's. Nothing consumes this
# configuration by source — it is a root config, applied directly — so an output
# here earns its place by being something a person types at a terminal, or
# something a manifest in gitops/ is checked against.
#
# That rules out two kinds of thing this file used to carry, and should not
# reacquire. Resource IDs: nobody reads a subnet ID off a terminal, and the ones
# that are needed are needed by Terraform, which has them already. And anything
# already in flux_post_build_substitutions: every client ID reaches the cluster
# through that map, so a second output naming one is a copy that can only drift.
#
# The test to apply before adding one: is it derivable from a variable, and would
# anyone type it? loki_storage_account_name passes because a random suffix makes it
# underivable; apps_dns_zone_name did not, because it is environment plus suffix.

output "resource_group_name" {
  description = "Name of the resource group containing the AKS cluster."
  value       = local.resource_group_name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = module.aks.name
}

output "private_fqdn" {
  description = "Private FQDN of the API server, served by the AKS-managed private.<region>.azmk8s.io zone. The only name this cluster answers to: enable_private_cluster_public_fqdn is false, so there is no publicly resolvable counterpart. It resolves from inside the VNet or a network linked to that zone, and nowhere else — from a GitHub runner, reach the cluster with `az aks command invoke` instead."
  value       = module.aks.private_fqdn
}

output "jumpbox_key_vault_name" {
  description = "Name of the Key Vault holding the jump box administrator password, or null when jumpbox_enabled is false. Reading it needs \"Key Vault Secrets User\" here — Bastion's Key Vault sign-in flow is SSH-key only, so for RDP the operator fetches the credential, not Bastion."
  value       = one(module.jumpbox_key_vault[*].name)
}

output "jumpbox_password_secret_name" {
  description = "Name of the Key Vault secret holding the jump box administrator password. Connect over Bastion with authentication type \"Password\" and username \"azureuser\", pasting the value of this secret."
  value       = local.jumpbox_key_vault_secrets["admin_password"].name
}

output "workload_key_vault_name" {
  description = "Name of the workload Key Vault, or null when workload_key_vault_enabled is false. Derived as \"kv-<workload_name>-<environment>-workload\", against the jump box vault's \"-jump\". The longer of the two, and so the one that caps workload_name at 8 characters."
  value       = one(module.workload_key_vault[*].name)
}

output "flux_post_build_substitutions" {
  description = "The variables Flux substitutes into the bootstrap Kustomization's manifests. Every placeholder usable in gitops/clusters/<environment>/ appears here; one that does not is replaced with an empty string at reconcile time rather than failing. None of these are secrets — a client ID names an identity, it does not authenticate as one."
  value       = local.flux_post_build_substitutions
}

output "gateway_internal_ip" {
  description = "Private address the internal load balancer in front of the Gateway API data plane answers on. Fixed rather than dynamic so it can be pointed at before the Service exists — which is what lets main.dns.tf publish a record for it at plan time. It is also the address a hosts entry uses when apps_dns_zone_name is null."
  value       = local.gateway_internal_ip
}

output "monitoring_node_selector" {
  description = "The label the monitoring node pool carries and the taint monitoring workloads must tolerate. Exposed so a Helm values file in gitops/ is not a second, silently divergent copy of what main.aks.tf sets — a mismatch schedules the observability stack onto the apps pool, where it competes with applications rather than being isolated from them."
  value = {
    node_selector = { workload = "monitoring" }
    toleration = {
      key      = "workload"
      operator = "Equal"
      value    = "monitoring"
      effect   = "NoSchedule"
    }
  }
}

output "workload_identity_subjects" {
  description = "The exact federated credential subjects, keyed by tenant name — \"system:serviceaccount:<namespace>:<service_account>\". Entra ID matches these by literal string, so this is what to diff against the manifests in gitops/ when a pod fails token exchange with AADSTS70021."
  value       = { for key, credentials in local.workload_identity_federated_credentials : key => credentials.kubernetes.subject }
}

output "node_resource_group_name" {
  description = "Name of the auto-generated resource group holding the cluster's node resources."
  value       = module.aks.node_resource_group_name
}

output "loki_storage_account_name" {
  description = "Name of the storage account holding Loki's chunks, index and rules. Globally unique, so it carries the naming module's random suffix rather than being derivable from workload_name and environment. Shared access keys are disabled on it: reaching this from the jump box means `az storage blob list --auth-mode login`, and an `--account-key` invocation will fail no matter which key is offered."
  value       = local.loki_storage_account_name
}

output "loki_identity_subject" {
  description = "The exact federated credential subject Entra ID matches for Loki — \"system:serviceaccount:monitoring:loki\". Matched by literal string and never normalised, so this is what to diff against the ServiceAccount in gitops/ when Loki logs AADSTS70021 on its first write."
  value       = "system:serviceaccount:${local.loki_service_account.namespace}:${local.loki_service_account.name}"
}
