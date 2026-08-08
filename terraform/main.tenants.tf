# Workload identity for tenant applications. Each identity is federated to one
# Kubernetes service account on this cluster's OIDC issuer, so a pod running as that
# service account exchanges its projected token for an Entra ID token — no client
# secret, no certificate, nothing in a Kubernetes Secret to leak or rotate.
#
# Three things have to line up for that to work, and only the first is Terraform's:
#
#   * the federated credential's subject, built from var.workload_identities;
#   * the ServiceAccount in gitops/, annotated with this identity's client ID as
#     azure.workload.identity/client-id;
#   * the pod template, labelled azure.workload.identity/use: "true", without which
#     the mutating webhook projects no token at all.
#
# The client ID is Azure-assigned and cannot be known before apply, so it is not
# hand-copied into the manifests: it is pushed into the Flux build as a post-build
# substitution. See local.flux_post_build_substitutions.
#
# The Key Vault grant is deliberately not set through this module's own
# role_assignments input, even though it supports one. Routing it through
# local.workload_key_vault_role_assignments keeps every grant on the workload vault
# in one readable place — which is what tests/keyvault.tftest.hcl asserts on — and
# means workload_key_vault_enabled = false drops the grants without needing a
# one(module.workload_key_vault[*].resource_id) that evaluates to null.
module "workload_identity" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source   = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version  = "~> 0.5"
  for_each = var.workload_identities

  name                = local.workload_identity_names[each.key]
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.tags

  federated_identity_credentials = local.workload_identity_federated_credentials[each.key]
}
