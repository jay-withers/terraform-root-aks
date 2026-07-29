# Node OS patching and Kubernetes upgrades are gated by maintenance windows
# whose *names* are what bind them to AKS's auto-upgrade channels — a typo in a
# name silently produces a window that gates nothing, so assert on them here.
# The azurerm provider is mocked, so these run with no Azure credentials —
# both locally (`make test`) and in CI (ci-terraform).

mock_provider "azurerm" {}

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

  # var.kubernetes_version is pinned, so the Kubernetes auto-upgrade channel is
  # off by default and its window would never fire.
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
