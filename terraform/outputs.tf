output "resource_group_name" {
  description = "Name of the resource group containing the AKS cluster."
  value       = local.resource_group_name
}

output "resource_group_id" {
  description = "Resource ID of the resource group containing the AKS cluster. Use as the scope when granting a role over everything this module creates."
  value       = local.resource_group_id
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
  value       = module.vnet.resource_id
}

output "virtual_network_name" {
  description = "Name of the cluster VNet."
  value       = module.vnet.name
}

output "node_subnet_id" {
  description = "Resource ID of the subnet holding the cluster nodes."
  value       = module.vnet.subnets["nodes"].resource_id
}

output "api_server_subnet_id" {
  description = "Resource ID of the subnet the API server is projected into by VNet integration."
  value       = module.vnet.subnets["api_server"].resource_id
}

output "privatelink_subnet_id" {
  description = "Resource ID of the subnet holding private endpoints, or null when workload_key_vault_enabled is false. Use as the subnet for further private endpoints rather than adding another subnet."
  value       = local.privatelink_subnet_id
}

output "jumpbox_id" {
  description = "Resource ID of the jump box VM, or null when jumpbox_enabled is false. Use as the scope when granting operators \"Virtual Machine Administrator Login\"."
  value       = one(module.jumpbox[*].resource_id)
}

output "jumpbox_private_ip" {
  description = "Private IP of the jump box, or null when jumpbox_enabled is false. Informational — connect through Bastion rather than to this address."
  value       = one(module.jumpbox[*].virtual_machine_azurerm.private_ip_address)
}

output "jumpbox_key_vault_name" {
  description = "Name of the Key Vault holding the jump box administrator password, or null when jumpbox_enabled is false. Reading it needs \"Key Vault Secrets User\" here — Bastion's Key Vault sign-in flow is SSH-key only, so for RDP the operator fetches the credential, not Bastion."
  value       = one(module.jumpbox_key_vault[*].name)
}

output "jumpbox_password_secret_name" {
  description = "Name of the Key Vault secret holding the jump box administrator password. Connect over Bastion with authentication type \"Password\" and username \"azureuser\", pasting the value of this secret."
  value       = local.jumpbox_key_vault_secrets["admin_password"].name
}

output "workload_key_vault_id" {
  description = "Resource ID of the workload Key Vault, or null when workload_key_vault_enabled is false. Use as the scope when granting a workload identity access outside this module."
  value       = one(module.workload_key_vault[*].resource_id)
}

output "workload_key_vault_name" {
  description = "Name of the workload Key Vault, or null when workload_key_vault_enabled is false. Derived as \"kv-<workload_name>-<environment>-workload\", against the jump box vault's \"-jump\". The longer of the two, and so the one that caps workload_name at 8 characters."
  value       = one(module.workload_key_vault[*].name)
}

output "workload_key_vault_uri" {
  description = "Data-plane URI of the workload Key Vault, or null when workload_key_vault_enabled is false. Resolves to the private endpoint's address from inside the VNet and to nothing usable from outside it — this is the value a SecretProviderClass takes as its keyvaultName's vault URI."
  value       = one(module.workload_key_vault[*].uri)
}

output "key_vault_private_dns_zone_id" {
  description = "Resource ID of the hub's privatelink.vaultcore.azure.net private DNS zone this cluster links to, or null when workload_key_vault_enabled is false. The zone is owned by the connectivity component, not by this module — other spokes link their own VNets to it the same way."
  value       = one(data.azurerm_private_dns_zone.key_vault[*].id)
}

output "hub_vnet_id" {
  description = "Resource ID of the hub virtual network this cluster is peered to."
  value       = data.azurerm_virtual_network.hub.id
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the user-assigned identity the cluster control plane runs as. Grant this rights on resources the control plane itself must reach, not workloads — those should use workload identity via oidc_issuer_url."
  value       = module.aks_identity.principal_id
}

output "oidc_issuer_url" {
  description = "Issuer URL of the cluster's OIDC endpoint. Required as the issuer when creating the federated identity credential that lets a Kubernetes service account authenticate to Entra ID via workload identity."
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "flux_extension_id" {
  description = "Resource ID of the microsoft.flux cluster extension, or null when flux_enabled is false."
  value       = one(azurerm_kubernetes_cluster_extension.flux[*].id)
}

output "flux_configuration_id" {
  description = "Resource ID of the Flux configuration reconciling the cluster, or null when no flux_git_repository_url is set. Null here with a non-null flux_extension_id means Flux is installed but syncing nothing."
  value       = one(azurerm_kubernetes_flux_configuration.this[*].id)
}

output "node_resource_group_name" {
  description = "Name of the auto-generated resource group holding the cluster's node resources."
  value       = module.aks.node_resource_group_name
}
