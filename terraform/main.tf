# CAF-compliant resource names, e.g. "aks-<workload_name>-<environment>". Also
# derives the name of the vended landing zone resource group this deploys into,
# which is looked up rather than created — see data.tf.
module "naming" {
  #checkov:skip=CKV_TF_1:Registry-sourced module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"

  suffix = [var.workload_name, var.environment]
}
