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

# --- networking -------------------------------------------------------------
# The cluster is private by design: the API server has no public endpoint, and
# is reachable only from inside the VNet or via `az aks command invoke`. See
# network.tf and locals.tf.
#
# The three ranges below must not overlap each other, the VNet, or anything the
# VNet is peered with or routed to. AKS rejects overlaps at create time, which
# is a slow way to find out.

variable "vnet_address_space" {
  description = "Address space of the cluster VNet. Must contain node_subnet_address_prefix and api_server_subnet_address_prefix, and must not overlap pod_cidr, service_cidr, or any peered network."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block."
  }
}

variable "node_subnet_address_prefix" {
  description = "Address prefix of the subnet holding the cluster nodes. Azure CNI Overlay places pods on pod_cidr rather than on VNet addresses, so this only has to accommodate the node count plus upgrade surge — not the pod count."
  type        = string
  default     = "10.0.0.0/22"

  validation {
    condition     = can(cidrhost(var.node_subnet_address_prefix, 0))
    error_message = "node_subnet_address_prefix must be a valid CIDR block."
  }
}

variable "api_server_subnet_address_prefix" {
  description = "Address prefix of the subnet the API server is projected into by VNet integration. Delegated to Microsoft.ContainerService/managedClusters and dedicated to the API server; AKS requires /28 or larger."
  type        = string
  default     = "10.0.4.0/28"

  validation {
    condition     = can(cidrhost(var.api_server_subnet_address_prefix, 0))
    error_message = "api_server_subnet_address_prefix must be a valid CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.api_server_subnet_address_prefix)[1]) <= 28
    error_message = "api_server_subnet_address_prefix must be /28 or larger — AKS rejects a smaller API server subnet."
  }
}

variable "pod_cidr" {
  description = "Address range pods are allocated from under Azure CNI Overlay. Routed only inside the cluster, so it never consumes VNet addresses; defaults to CGNAT space to keep it clear of RFC1918 networks the VNet might peer with."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR block."
  }
}

variable "service_cidr" {
  description = "Address range Kubernetes ClusterIP services are allocated from. Virtual to the cluster and never routed on the VNet, but must still not overlap it. The kube-dns service IP is derived from this as its tenth address."
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 10))
    error_message = "service_cidr must be a valid CIDR block with room for at least ten addresses."
  }
}

# --- jump box ---------------------------------------------------------------
# The administrative path into the private cluster. See jumpbox.tf.

variable "jumpbox_enabled" {
  description = "Whether to create the jump box and its subnet. Turning this off leaves the cluster reachable only through `az aks command invoke` or a network path added elsewhere, so make sure one exists first."
  type        = bool
  default     = true
}

variable "jumpbox_subnet_address_prefix" {
  description = "Address prefix of the jump box subnet. Sized for a single VM; must sit inside vnet_address_space and not overlap the node or API server subnets."
  type        = string
  default     = "10.0.5.0/28"

  validation {
    condition     = can(cidrhost(var.jumpbox_subnet_address_prefix, 0))
    error_message = "jumpbox_subnet_address_prefix must be a valid CIDR block."
  }
}

variable "jumpbox_vm_size" {
  description = "VM size for the jump box. Burstable by default — it spends most of its life idle, and the work it does (kubectl, helm, az) is interactive rather than sustained. Deallocate it when unused; compute stops billing, the disk does not."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "jumpbox_key_expiry_date" {
  description = "Optional RFC3339 expiry for the jump box SSH key secret, e.g. \"2027-01-01T00:00:00Z\". Null by default: Key Vault refuses to serve an expired secret, so a date nobody is watching locks everyone out of the only route into the cluster. Set it once a rotation process exists to meet it — rotation is a replace of tls_private_key.jumpbox_admin, not a re-apply."
  type        = string
  default     = null

  validation {
    condition     = var.jumpbox_key_expiry_date == null || can(formatdate("YYYY-MM-DD", var.jumpbox_key_expiry_date))
    error_message = "jumpbox_key_expiry_date must be an RFC3339 timestamp, e.g. \"2027-01-01T00:00:00Z\"."
  }
}

variable "bastion_enabled" {
  description = "Whether to create the Azure Bastion host that fronts the jump box. The Developer SKU is free and needs no dedicated subnet, but is not offered in every region — set this to false where var.location does not support it. Inert unless jumpbox_enabled is true."
  type        = bool
  default     = true
}

variable "sku_tier" {
  description = "AKS control plane pricing tier. One of \"Free\", \"Standard\", or \"Premium\". Standard adds the financially-backed API server uptime SLA — recommended for zone-resilient/production clusters."
  type        = string
  default     = "Standard"
}

# --- upgrades and maintenance ----------------------------------------------
# Two independent auto-upgrade channels — node OS image and Kubernetes version —
# each gated by its own maintenance window.

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

# Authentication and authorization take no inputs by design — Entra ID with Azure
# RBAC, local accounts off, workload identity on. See locals.tf and main.tf.

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
