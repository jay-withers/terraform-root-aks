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

output "oidc_issuer_url" {
  description = "Issuer URL of the cluster's OIDC endpoint. Required as the issuer when creating the federated identity credential that lets a Kubernetes service account authenticate to Entra ID via workload identity."
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "node_resource_group_name" {
  description = "Name of the auto-generated resource group holding the cluster's node resources."
  value       = module.aks.node_resource_group_name
}
