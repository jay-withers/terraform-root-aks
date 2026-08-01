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

output "private_fqdn" {
  description = "Private FQDN of the API server, served by the AKS-managed private.<region>.azmk8s.io zone. Only resolves from inside the VNet or a network linked to that zone — prefer the fqdn output, which resolves anywhere and points at the same private address."
  value       = module.aks.private_fqdn
}

output "virtual_network_id" {
  description = "Resource ID of the cluster VNet. Use as the remote side when peering, or as the target of a private DNS zone virtual network link."
  value       = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  description = "Name of the cluster VNet."
  value       = azurerm_virtual_network.this.name
}

output "node_subnet_id" {
  description = "Resource ID of the subnet holding the cluster nodes."
  value       = azurerm_subnet.nodes.id
}

output "api_server_subnet_id" {
  description = "Resource ID of the subnet the API server is projected into by VNet integration."
  value       = azurerm_subnet.api_server.id
}

output "jumpbox_id" {
  description = "Resource ID of the jump box VM, or null when jumpbox_enabled is false. Use as the scope when granting operators \"Virtual Machine Administrator Login\"."
  value       = one(azurerm_linux_virtual_machine.jumpbox[*].id)
}

output "jumpbox_private_ip" {
  description = "Private IP of the jump box, or null when jumpbox_enabled is false. Informational — connect through Bastion rather than to this address."
  value       = one(azurerm_linux_virtual_machine.jumpbox[*].private_ip_address)
}

output "jumpbox_key_vault_name" {
  description = "Name of the Key Vault holding the jump box SSH private key, or null when jumpbox_enabled is false. Select this vault in the Bastion connection pane."
  value       = one(azurerm_key_vault.jumpbox[*].name)
}

output "jumpbox_ssh_secret_name" {
  description = "Name of the Key Vault secret holding the jump box SSH private key. Connect with authentication type \"SSH Private Key from Azure Key Vault\" and username \"azureuser\"."
  value       = one(azurerm_key_vault_secret.jumpbox_ssh_private_key[*].name)
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the user-assigned identity the cluster control plane runs as. Grant this rights on resources the control plane itself must reach, not workloads — those should use workload identity via oidc_issuer_url."
  value       = azurerm_user_assigned_identity.aks.principal_id
}

output "oidc_issuer_url" {
  description = "Issuer URL of the cluster's OIDC endpoint. Required as the issuer when creating the federated identity credential that lets a Kubernetes service account authenticate to Entra ID via workload identity."
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "node_resource_group_name" {
  description = "Name of the auto-generated resource group holding the cluster's node resources."
  value       = module.aks.node_resource_group_name
}
