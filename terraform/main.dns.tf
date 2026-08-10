# Name resolution for the hostnames the cluster publishes.
#
# Unlike privatelink.vaultcore.azure.net — which the hub owns, because a zone of that
# name is shared by every spoke that talks to a Key Vault — this zone is this
# cluster's alone. Nothing outside the spoke serves a name under it, and the names
# stop meaning anything the moment the cluster is gone, so the zone is created here
# and destroyed with it. Ownership follows whether the zone outlives the spoke.
#
# The name carries the environment (dev.apps.internal, and so on) rather than being
# the same string in all three. A private DNS zone is only visible to the VNets it is
# linked to, so three zones called apps.internal do work — right up until anything
# needs to resolve across them, at which point a VNet can link to only one zone of a
# given name and the collision has to be undone with records already in it.
resource "azurerm_private_dns_zone" "apps" {
  count = local.apps_dns_zone_enabled ? 1 : 0

  name                = local.apps_dns_zone_name
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

# Only this VNet. The jump box is in it, which is what makes the names resolvable
# from where they are used. Linking the hub would need Microsoft.Network/
# virtualNetworks/join/action on the hub VNet, and the vended identity holds a
# five-action peering role there and deliberately nothing broader — so a hub link is
# a grant in the landing zone repo, not a line here.
resource "azurerm_private_dns_zone_virtual_network_link" "apps" {
  count = local.apps_dns_zone_enabled ? 1 : 0

  name                  = "vnetlink-${local.name_suffix}"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.apps[0].name
  virtual_network_id    = module.vnet.resource_id
  tags                  = local.tags

  # Records are written by external-dns from inside the cluster, and a VM that
  # self-registered would be claiming a name in a zone that describes HTTPRoutes.
  registration_enabled = false
}

# Terraform creates the zone and stops. The records in it are external-dns's, written
# from what is actually published: one A record per HTTPRoute hostname, removed when
# the route is, each paired with a TXT record naming the cluster that owns it.
#
# The alternative was a wildcard A record here, which needs no controller and no
# identity — and makes DNS answer for every name whether or not anything serves it,
# so it can never be asked what the cluster publishes. That trade is worth making for
# the certificate in gitops/infrastructure/configs/gateway.yaml, where the cost of a
# name is a private CA signature. It is not worth making for the record that decides
# whether a request arrives at all.
#
# This identity is deliberately not an entry in var.workload_identities. That map is
# tenant workloads — it carries an opt-in to the workload Key Vault and its keys name
# tenants. external-dns is platform infrastructure that happens to run as a pod.
module "external_dns_identity" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "~> 0.5"
  count   = local.apps_dns_zone_enabled ? 1 : 0

  name                = "${module.naming.user_assigned_identity.name}-external-dns"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.tags

  federated_identity_credentials = {
    kubernetes = {
      name     = "fic-external-dns"
      audience = ["api://AzureADTokenExchange"]
      issuer   = module.aks.oidc_issuer_profile_issuer_url

      # Matched by Entra ID as a literal string and never normalised. The namespace
      # and service account are external-dns's chart defaults, held in
      # local.external_dns_service_account so the manifests and this cannot drift.
      subject = "system:serviceaccount:${local.external_dns_service_account.namespace}:${local.external_dns_service_account.name}"
    }
  }
}

# Scoped to the zone, not to the resource group. Private DNS Zone Contributor at
# group scope would let a compromised external-dns rewrite privatelink records for
# any zone that later lands here — including the ones that decide where Key Vault
# traffic goes. At zone scope the worst it can do is misdirect the names it is
# already responsible for.
resource "azurerm_role_assignment" "external_dns" {
  count = local.apps_dns_zone_enabled ? 1 : 0

  scope                = azurerm_private_dns_zone.apps[0].id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = module.external_dns_identity[0].principal_id
}

# Reading the zone list is a subscription-scope operation, and external-dns issues it
# at startup to resolve a zone name to its resource ID. Reader on the resource group
# is the narrowest scope that satisfies it — the role grants no write anywhere, and
# the write it does need is the assignment above.
resource "azurerm_role_assignment" "external_dns_zone_reader" {
  count = local.apps_dns_zone_enabled ? 1 : 0

  scope                = data.azurerm_resource_group.landing_zone.id
  role_definition_name = "Reader"
  principal_id         = module.external_dns_identity[0].principal_id
}
