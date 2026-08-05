# A typo in a maintenance configuration name silently produces a window that
# gates nothing, so the reserved names are asserted here.

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

run "node_os_window_uses_reserved_name" {
  command = plan

  assert {
    condition     = local.maintenance_configuration["node_os"].name == "aksManagedNodeOSUpgradeSchedule"
    error_message = "node OS maintenance window must use the reserved name AKS binds to the node OS upgrade channel"
  }

  assert {
    condition     = local.maintenance_configuration["node_os"].maintenance_window.schedule.daily.interval_days == 1
    error_message = "node OS maintenance window did not default to a nightly schedule"
  }
}

run "windows_send_a_start_date" {
  command = plan

  variables {
    kubernetes_upgrade_channel = "patch"
  }

  # A null start_date is not a no-op: AKS fills it with the creation date and keeps
  # it, so Terraform proposes startDate -> null on every plan and the apply is
  # reverted server-side. The value only sets when the window first becomes active.
  assert {
    condition = alltrue([
      local.maintenance_configuration["node_os"].maintenance_window.start_date != null,
      local.maintenance_configuration["cluster"].maintenance_window.start_date != null,
    ])
    error_message = "both maintenance windows must send a start_date, or every plan shows a startDate diff that never converges"
  }
}

run "rejects_a_start_date_that_is_not_a_date" {
  command = plan

  variables {
    node_os_maintenance_window = {
      start_date = "01-01-2024"
    }
  }

  expect_failures = [var.node_os_maintenance_window]
}

run "cluster_window_absent_while_channel_is_none" {
  command = plan

  assert {
    condition     = !contains(keys(local.maintenance_configuration), "cluster")
    error_message = "cluster maintenance window should not be created while kubernetes_upgrade_channel is \"none\""
  }
}

run "cluster_window_created_when_channel_enabled" {
  command = plan

  variables {
    kubernetes_upgrade_channel = "patch"
  }

  assert {
    condition     = local.maintenance_configuration["cluster"].name == "aksManagedAutoUpgradeSchedule"
    error_message = "cluster maintenance window must use the reserved name AKS binds to the Kubernetes auto-upgrade channel"
  }

  assert {
    condition     = local.maintenance_configuration["cluster"].maintenance_window.schedule.weekly.day_of_week == "Sunday"
    error_message = "cluster maintenance window did not default to Sunday"
  }
}

run "rejects_window_shorter_than_four_hours" {
  command = plan

  variables {
    node_os_maintenance_window = {
      duration_hours = 2
    }
  }

  expect_failures = [var.node_os_maintenance_window]
}

run "rejects_unknown_node_os_channel" {
  command = plan

  variables {
    node_os_upgrade_channel = "Latest"
  }

  expect_failures = [var.node_os_upgrade_channel]
}
