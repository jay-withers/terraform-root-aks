# Module tests. The azurerm provider is mocked, so these run with no Azure
# credentials — both locally (`make test`) and in CI (ci-terraform).
#
# Add `assert` blocks as the module grows; see the commented example below.

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

run "plan_with_defaults" {
  command = plan

  # Example assertion — uncomment once the module creates resources/outputs:
  #
  # assert {
  #   condition     = output.cluster_name == module.naming.kubernetes_cluster.name
  #   error_message = "cluster name did not match the generated default"
  # }
}
