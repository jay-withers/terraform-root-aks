# A typo in a maintenance configuration name silently produces a window that
# gates nothing, so the reserved names are asserted here.

mock_provider "azurerm" {
  # azurerm_key_vault validates tenant_id as a UUID at plan time; the provider
  # mock otherwise generates a random string.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
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
