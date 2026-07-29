variable "workload_name" {
  description = "Name of the workload this cluster serves. Combined with environment to derive the CAF-compliant cluster and resource group names via the Azure naming module."
  type        = string
  default     = "main"
}

variable "environment" {
  description = "Deployment environment. Used to derive the default resource name and tag, and to gate environment-specific behaviour."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of \"dev\", \"stg\", or \"prd\"."
  }
}

variable "location" {
  description = "Azure region to deploy into."
  type        = string
  default     = "westeurope"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster. Pinned for reproducible clusters; bump deliberately (AKS only supports upgrades to newer versions, never downgrades)."
  type        = string
  default     = "1.34.8"
}

# --- system pool (mode System) --------------------------------------------
# Runs cluster-critical add-ons only. Tainted CriticalAddonsOnly=true:NoSchedule
# in main.tf so application workloads land on the apps/monitoring pools instead.

variable "system_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool. Defaults to one per availability zone for zone resilience."
  type        = number
  default     = 3
}

# --- apps pool (mode User) -------------------------------------------------
# Default landing zone for application workloads. Untainted.

variable "apps_vm_size" {
  description = "VM size for the apps node pool."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "apps_min_count" {
  description = "Minimum node count for the autoscaled apps node pool. Defaults to one per availability zone for zone resilience."
  type        = number
  default     = 3
}

variable "apps_max_count" {
  description = "Maximum node count for the autoscaled apps node pool."
  type        = number
  default     = 6
}

# --- monitoring pool (mode User) -------------------------------------------
# Isolated for the observability stack (Prometheus/Grafana/Loki). Tainted
# workload=monitoring:NoSchedule and labelled workload=monitoring in main.tf;
# monitoring workloads must set a matching toleration and nodeSelector.

variable "monitoring_vm_size" {
  description = "VM size for the monitoring node pool."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "monitoring_min_count" {
  description = "Minimum node count for the autoscaled monitoring node pool. Defaults to one per availability zone for zone resilience."
  type        = number
  default     = 3
}

variable "monitoring_max_count" {
  description = "Maximum node count for the autoscaled monitoring node pool."
  type        = number
  default     = 6
}

variable "availability_zones" {
  description = "Availability zones to spread every node pool across. Defaults to all three zones for zone resilience; set to [] to disable zone pinning (regional). The chosen VM size must be available in each listed zone in the target region."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "sku_tier" {
  description = "AKS control plane pricing tier. One of \"Free\", \"Standard\", or \"Premium\". Standard adds the financially-backed API server uptime SLA — recommended for zone-resilient/production clusters."
  type        = string
  default     = "Standard"
}

# --- upgrades and maintenance ----------------------------------------------
# AKS has two independent auto-upgrade channels: one for the node OS image and
# one for the Kubernetes version. Each is gated by a maintenance window with a
# reserved name (see locals.tf) — without a window, upgrades land at a time of
# Azure's choosing.

variable "node_os_upgrade_channel" {
  description = "How node OS updates are applied. \"NodeImage\" upgrades to the latest AKS-validated node image; \"SecurityPatch\" applies OS security patches in place; \"Unmanaged\" leaves patching to the OS's own updater; \"None\" disables it. Constrained to node_os_maintenance_window."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be one of \"NodeImage\", \"SecurityPatch\", \"Unmanaged\", or \"None\"."
  }
}

variable "kubernetes_upgrade_channel" {
  description = "Auto-upgrade channel for the Kubernetes version itself. Defaults to \"none\" because var.kubernetes_version is pinned — anything else lets AKS move the version out from under Terraform, which then reports drift on every plan. Enable only alongside unpinning kubernetes_version. When not \"none\", cluster_maintenance_window applies."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "patch", "stable", "rapid", "node-image"], var.kubernetes_upgrade_channel)
    error_message = "kubernetes_upgrade_channel must be one of \"none\", \"patch\", \"stable\", \"rapid\", or \"node-image\"."
  }
}

variable "node_os_maintenance_window" {
  description = "When node OS updates are allowed to run. Defaults to a daily 4-hour window from 19:00 UTC. Times are in UTC unless utc_offset says otherwise; duration_hours must be 4-24."
  type = object({
    start_time     = optional(string, "19:00")
    duration_hours = optional(number, 4)
    interval_days  = optional(number, 1)
    utc_offset     = optional(string, "+00:00")
  })
  default = {}

  validation {
    condition     = var.node_os_maintenance_window.duration_hours >= 4 && var.node_os_maintenance_window.duration_hours <= 24
    error_message = "node_os_maintenance_window.duration_hours must be between 4 and 24."
  }
}

variable "cluster_maintenance_window" {
  description = "When Kubernetes version auto-upgrades are allowed to run. Inert unless kubernetes_upgrade_channel is set to something other than \"none\". Defaults to a weekly 4-hour window from 06:00 UTC on Sunday, clear of the daily node OS window; duration_hours must be 4-24."
  type = object({
    day_of_week    = optional(string, "Sunday")
    start_time     = optional(string, "06:00")
    duration_hours = optional(number, 4)
    interval_weeks = optional(number, 1)
    utc_offset     = optional(string, "+00:00")
  })
  default = {}

  validation {
    condition     = var.cluster_maintenance_window.duration_hours >= 4 && var.cluster_maintenance_window.duration_hours <= 24
    error_message = "cluster_maintenance_window.duration_hours must be between 4 and 24."
  }

  validation {
    condition     = contains(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"], var.cluster_maintenance_window.day_of_week)
    error_message = "cluster_maintenance_window.day_of_week must be a full English day name, e.g. \"Sunday\"."
  }
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
