# The workload vault's whole value is that it has no public endpoint, and every
# property below fails silently: a vault with public access left on still works,
# still serves secrets, and still looks correct in a plan.

mock_provider "azurerm" {
  # The landing zone resource group, the hub VNet and the hub's private DNS zone are
  # looked up, not created (see data.tf). Their IDs are fed to AVM modules that
  # validate the resource ID format; the provider mock otherwise generates a random
  # string. Names here are fixed rather than derived — assertions about derived names
  # use module.naming, which is real.
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-aks-dev"
      name     = "rg-aks-dev"
      location = "westeurope"
    }
  }

  mock_data "azurerm_virtual_network" {
    defaults = {
      id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub-dev/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev"
      name = "vnet-hub-dev"
    }
  }

  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub-dev/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      name = "privatelink.vaultcore.azure.net"
    }
  }

  # azurerm_key_vault validates tenant_id as a UUID at plan time; the provider
  # mock otherwise generates a random string.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

# The AVM modules reach Azure through azapi, and build resource IDs from the
# client config — an unmocked subscription_id fails ID validation at plan time.
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "22222222-2222-2222-2222-222222222222"
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
    }
  }
}
mock_provider "tls" {}

run "workload_vault_has_no_public_endpoint" {
  command = plan

  assert {
    condition     = !local.workload_key_vault_network.public_network_access_enabled
    error_message = "the workload vault must have no public endpoint — that is the only thing separating it from the jump box vault, which does"
  }

  # Default-deny behind the closed public endpoint, not instead of it.
  assert {
    condition     = local.workload_key_vault_network.network_acls.default_action == "Deny"
    error_message = "the workload vault's firewall must default to deny"
  }

  # "AzureServices" would admit any Microsoft-operated service.
  assert {
    condition     = local.workload_key_vault_network.network_acls.bypass == "None"
    error_message = "the workload vault must not bypass its firewall for Azure services"
  }
}

run "workload_vault_is_reachable_over_a_private_endpoint" {
  command = plan

  # Without an endpoint, closing the public one leaves the vault unreachable.
  assert {
    condition     = length(local.workload_key_vault_private_endpoints) == 1
    error_message = "the workload vault needs a private endpoint; with public access off there is no other path to its data plane"
  }

  # With no zone group the endpoint has an address nothing can resolve — clients keep
  # resolving the public name to a public IP the vault no longer answers on.
  assert {
    condition     = length(local.workload_key_vault_private_endpoints["vault"].private_dns_zone_resource_ids) == 1
    error_message = "the private endpoint must be joined to a private DNS zone, or the vault resolves to an address that no longer answers"
  }

  # The resource ID is unknown until apply, so this pins the subnet, not the ID.
  assert {
    condition     = contains(keys(local.subnets), "privatelink")
    error_message = "the private endpoint needs the private link subnet, which follows workload_key_vault_enabled"
  }
}

run "workload_vault_grants_are_least_privilege" {
  command = plan

  variables {
    workload_key_vault_secrets_users = ["22222222-2222-2222-2222-222222222222"]
  }

  # Read-only: a workload mounting secrets has no reason to write or delete them.
  assert {
    condition     = local.workload_key_vault_role_assignments["secrets_user_0"].role_definition_id_or_name == "Key Vault Secrets User"
    error_message = "workload identities must get read-only access to secret values, not the Officer role"
  }

  assert {
    condition     = local.workload_key_vault_role_assignments["deployer"].role_definition_id_or_name == "Key Vault Secrets Officer"
    error_message = "the deploying identity must hold data-plane rights; in RBAC mode Owner does not confer them"
  }
}

run "no_workload_vault_leaves_no_private_networking_behind" {
  command = plan

  variables {
    workload_key_vault_enabled = false
  }

  assert {
    condition     = length(module.workload_key_vault) == 0
    error_message = "workload_key_vault_enabled = false must create no vault"
  }

  # All of it exists only to serve the vault, and the first two bill for themselves.
  assert {
    condition = alltrue([
      length(azurerm_private_dns_zone_virtual_network_link.key_vault) == 0,
      length(module.nsg_privatelink) == 0,
      !contains(keys(local.subnets), "privatelink"),
    ])
    error_message = "workload_key_vault_enabled = false must leave no private endpoint scaffolding behind"
  }
}
