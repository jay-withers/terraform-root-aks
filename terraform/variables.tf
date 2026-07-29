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

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
