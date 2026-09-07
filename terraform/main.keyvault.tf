# Application secrets, answering only on a private endpoint in snet-privatelink.
# Reaching the data plane means being on the VNet — so Terraform cannot seed secrets
# here either. This creates the vault and the RBAC grants; the secrets are written
# from the jump box. Costs a few pounds a month for the endpoint and zone.

# Without a zone the endpoint has an address nothing can resolve: clients would keep
# resolving the public name to a public IP the vault no longer answers on.
#
# The zone itself lives in the hub and is not created here — a VNet links to only one
# zone of a given name, and the zone outlives any single spoke. This creates only the
# link, which is a child of the zone and so is written in the hub's resource group.
# That is what the landingzones component's per-zone Private DNS Zone Contributor
# grant is for, and why it is scoped to the specific zones this cluster was given
# rather than to the hub group as a whole.
#
# Destroying this cluster removes its link and leaves the zone standing.
resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count = var.workload_key_vault_enabled ? 1 : 0

  name                  = "vnetlink-${local.name_suffix}"
  resource_group_name   = module.hub_naming.resource_group.name
  private_dns_zone_name = data.azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = module.vnet.resource_id
  tags                  = local.tags

  # Records come from the endpoint's DNS zone group; nothing self-registers here.
  registration_enabled = false
}

module "workload_key_vault" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.11"
  count   = var.workload_key_vault_enabled ? 1 : 0

  name                = local.workload_key_vault_name
  location            = local.location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # In locals.tf so tests can assert on them — a module's inputs are not reachable
  # from a `run` block, but the values that fed them are.
  public_network_access_enabled = local.workload_key_vault_network.public_network_access_enabled
  network_acls                  = local.workload_key_vault_network.network_acls
  private_endpoints             = local.workload_key_vault_private_endpoints
  role_assignments              = local.workload_key_vault_role_assignments
}
