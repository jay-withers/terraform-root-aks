locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })

  # admin_group_object_ids is omitted deliberately: AKS binds those groups
  # straight to cluster-admin, which no Azure role assignment can revoke. Grant
  # admin with the "Azure Kubernetes Service RBAC Cluster Admin" role instead.
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
    tenant_id         = data.azurerm_client_config.current.tenant_id
  }

  # These names are reserved: AKS binds a maintenance window to an auto-upgrade
  # channel by name alone, and any other name gates nothing.
  maintenance_configuration = merge(
    {
      node_os = {
        name = "aksManagedNodeOSUpgradeSchedule"
        maintenance_window = {
          duration_hours = var.node_os_maintenance_window.duration_hours
          start_time     = var.node_os_maintenance_window.start_time
          utc_offset     = var.node_os_maintenance_window.utc_offset
          schedule = {
            daily = {
              interval_days = var.node_os_maintenance_window.interval_days
            }
          }
        }
      }
    },
    # Inert unless the Kubernetes auto-upgrade channel is on.
    var.kubernetes_upgrade_channel == "none" ? {} : {
      cluster = {
        name = "aksManagedAutoUpgradeSchedule"
        maintenance_window = {
          duration_hours = var.cluster_maintenance_window.duration_hours
          start_time     = var.cluster_maintenance_window.start_time
          utc_offset     = var.cluster_maintenance_window.utc_offset
          schedule = {
            weekly = {
              day_of_week    = var.cluster_maintenance_window.day_of_week
              interval_weeks = var.cluster_maintenance_window.interval_weeks
            }
          }
        }
      }
    }
  )
}
