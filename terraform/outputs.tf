output "resource_group_name" {
  description = "Name of the resource group containing the AKS cluster."
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = module.aks.name
}

output "cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = module.aks.resource_id
}

output "fqdn" {
  description = "FQDN of the AKS cluster API server."
  value       = module.aks.fqdn
}

output "node_resource_group_name" {
  description = "Name of the auto-generated resource group holding the cluster's node resources."
  value       = module.aks.node_resource_group_name
}
