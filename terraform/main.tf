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

  # AKS layers Azure RBAC on top of the Kubernetes RBAC authorizer, so
  # enableAzureRBAC is rejected unless enableRBAC is also true.
  enable_rbac = true
  aad_profile = local.aad_profile

  disable_local_accounts = true

  # Workload identity requires the OIDC issuer.
  oidc_issuer_profile = {
    enabled = true
  }

  security_profile = {
    workload_identity = {
      enabled = true
    }

    # 24h is the shortest interval AKS accepts.
    image_cleaner = {
      enabled        = true
      interval_hours = 24
    }
  }

  # enable_secret_rotation polls Key Vault and refreshes already-mounted files and
  # synced Secrets; it rotates nothing in Key Vault, and env vars still need a
  # pod restart.
  addon_profile_key_vault_secrets_provider = {
    enabled = true
    config = {
      enable_secret_rotation = true
    }
  }

  auto_upgrade_profile = {
    node_os_upgrade_channel = var.node_os_upgrade_channel
    upgrade_channel         = var.kubernetes_upgrade_channel
  }

  # Constrains when the channels above are allowed to act.
  maintenanceconfiguration = local.maintenance_configuration

  tags = local.tags
}
