# Tenant of the identity running Terraform; used as the cluster's Entra ID tenant.
data "azurerm_client_config" "current" {}

# The landing zone this cluster deploys into. It is vended by the azure-landingzone
# repo's `landingzones` component, not created here — the resource group *is* the
# landing zone, and the identity this runs as has no rights to create resource
# groups. Applying before that component fails with a "not found", which is correct:
# there is nowhere to deploy.
#
# Its region is authoritative for everything here, which is why this module no longer
# takes a location variable — a second source of truth for region could only ever
# disagree with the group the resources live in.
data "azurerm_resource_group" "landing_zone" {
  name = module.naming.resource_group.name
}

# The hub, located by driving the naming module with the hub's suffix rather than by
# reading the connectivity component's state. See the naming contract in the
# azure-landingzone README for why this is a lookup and not terraform_remote_state.
module "hub_naming" {
  #checkov:skip=CKV_TF_1:Registry-sourced module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"

  suffix = [var.hub_workload, var.environment]
}

data "azurerm_virtual_network" "hub" {
  name                = module.hub_naming.virtual_network.name
  resource_group_name = module.hub_naming.resource_group.name
}

# Hosted in the hub so the zone outlives this cluster: tearing the spoke down must
# leave it standing, since a zone is shared by every spoke that resolves against it.
# This module creates only its own virtual network link — see main.keyvault.tf.
data "azurerm_private_dns_zone" "key_vault" {
  count = var.workload_key_vault_enabled ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = module.hub_naming.resource_group.name
}

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = module.hub_naming.resource_group.name
}
