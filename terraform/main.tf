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
