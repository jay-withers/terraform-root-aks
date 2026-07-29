locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })

  # "aksManagedNodeOSUpgradeSchedule" and "aksManagedAutoUpgradeSchedule" are
  # reserved names: AKS binds a maintenance configuration to an auto-upgrade
  # channel by name alone. Any other name creates a generic maintenance window
  # that does *not* gate upgrades, so these strings must be exact.
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
    # Only created when the Kubernetes auto-upgrade channel is on; with the
    # channel at "none" the window would never fire.
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
