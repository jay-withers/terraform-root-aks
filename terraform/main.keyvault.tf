# Application secrets, answering only on a private endpoint in snet-privatelink.
# Reaching the data plane means being on the VNet — so Terraform cannot seed secrets
# here either. This creates the vault and the RBAC grants; the secrets are written
# from the jump box. Costs a few pounds a month for the endpoint and zone.

# Without this zone the endpoint has an address nothing can resolve: clients would
# keep resolving the public name to a public IP the vault no longer answers on. A
# VNet links to only one zone of a given name, so where a hub owns DNS centrally,
# set workload_key_vault_enabled = false and create the vault against the hub's zone.
module "key_vault_private_dns_zone" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "~> 0.5"
  count   = var.workload_key_vault_enabled ? 1 : 0

  domain_name = "privatelink.vaultcore.azure.net"
  parent_id   = module.resource_group.resource_id
  tags        = local.tags

  virtual_network_links = {
    cluster_vnet = {
      name               = "vnetlink-${local.name_suffix}"
      virtual_network_id = module.vnet.resource_id

      # Records come from the endpoint's DNS zone group; nothing self-registers here.
      registration_enabled = false
    }
  }
}

module "workload_key_vault" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10"
  count   = var.workload_key_vault_enabled ? 1 : 0

  name                = local.workload_key_vault_name
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
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
