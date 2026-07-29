# CAF-compliant resource names, e.g. "rg-<workload_name>-<environment>" and
# "aks-<workload_name>-<environment>".
module "naming" {
  #checkov:skip=CKV_TF_1:Registry-sourced module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"

  suffix = [var.workload_name, var.environment]
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name
  location = var.location
  tags     = local.tags
}

module "aks" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "~> 0.6"

  name      = module.naming.kubernetes_cluster.name
  location  = azurerm_resource_group.this.location
  parent_id = azurerm_resource_group.this.id

  kubernetes_version = var.kubernetes_version

  # System pool: cluster-critical add-ons only. The CriticalAddonsOnly taint
  # keeps application workloads off it — they schedule onto apps/monitoring.
  default_agent_pool = {
    name               = "system"
    mode               = "System"
    vm_size            = var.system_vm_size
    count_of           = var.system_node_count
    availability_zones = var.availability_zones
    node_taints        = ["CriticalAddonsOnly=true:NoSchedule"]
  }

  agent_pools = {
    # Default landing zone for application workloads. Untainted.
    apps = {
      name                = "apps"
      mode                = "User"
      vm_size             = var.apps_vm_size
      availability_zones  = var.availability_zones
      enable_auto_scaling = true
      min_count           = var.apps_min_count
      max_count           = var.apps_max_count
      count_of            = var.apps_min_count
    }

    # Isolated for the observability stack. Monitoring workloads must set a
    # toleration for workload=monitoring:NoSchedule and a matching nodeSelector.
    monitoring = {
      name                = "monitoring"
      mode                = "User"
      vm_size             = var.monitoring_vm_size
      availability_zones  = var.availability_zones
      enable_auto_scaling = true
      min_count           = var.monitoring_min_count
      max_count           = var.monitoring_max_count
      count_of            = var.monitoring_min_count
      node_labels         = { workload = "monitoring" }
      node_taints         = ["workload=monitoring:NoSchedule"]
    }
  }

  sku = {
    name = "Base"
    tier = var.sku_tier
  }

  # Node OS patching is automated; the Kubernetes version stays pinned to
  # var.kubernetes_version and is bumped deliberately through Terraform.
  auto_upgrade_profile = {
    node_os_upgrade_channel = var.node_os_upgrade_channel
    upgrade_channel         = var.kubernetes_upgrade_channel
  }

  # Windows constraining the channels above. Without these, AKS applies node
  # image upgrades whenever it likes, including mid-business-hours.
  maintenanceconfiguration = local.maintenance_configuration

  tags = local.tags
}
