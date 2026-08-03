# A private cluster has to bring its own VNet — AKS will only place a private
# API server and its node pools in a network it does not own. Note that both
# api_server_access_profile.enable_private_cluster and
# network_profile.outbound_type are create-time only: changing either replaces
# the cluster.
#
# Subnets are child resources of the VNet in the AVM module, so NSG association,
# delegation and role assignments are subnet properties rather than resources of
# their own. Definitions are in local.subnets. This also retires the
# `ignore_changes = [delegation]` the API server subnet used to need: azapi diffs
# only what it sends, and the module sends no action list for AKS to rewrite.

# Both NSGs are intentionally ruleless. Azure's own default rules already give
# exactly the posture a private cluster wants — inbound allowed from the VNet and
# from the AzureLoadBalancer health probes, everything else denied; outbound
# allowed to the VNet and the internet, which is what the loadBalancer egress
# path needs.
#
# Note the consequence: a Service of type LoadBalancer with a public IP will not
# work as-is. AKS adds its allow rules to the NSG it manages on the node NICs in
# the node resource group, not to these, so client traffic is dropped at the
# subnet. Exposing something publicly means an explicit inbound rule here — which
# for a private cluster should be a deliberate act, not a default.
module "nsg_nodes" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5"

  name                = "${module.naming.network_security_group.name}-nodes"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

module "nsg_api_server" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5"

  name                = "${module.naming.network_security_group.name}-apiserver"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

# Ruleless like the two above. Note it governs the subnet, not the endpoints in it:
# private endpoint traffic bypasses NSG rules while privateEndpointNetworkPolicies
# stays disabled.
module "nsg_privatelink" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5"
  count   = local.privatelink_enabled ? 1 : 0

  name                = "${module.naming.network_security_group.name}-privatelink"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}

module "vnet" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.20"

  name          = module.naming.virtual_network.name
  location      = module.resource_group.location
  parent_id     = module.resource_group.resource_id
  address_space = [var.vnet_address_space]
  subnets       = local.subnets
  tags          = local.tags
}

# BYO networking rules out a system-assigned identity: the cluster's rights on
# these subnets have to exist before the cluster does, and a system-assigned
# identity is not created until then. The grants themselves are properties of the
# subnets — see local.subnets.
module "aks_identity" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "~> 0.5"

  name                = module.naming.user_assigned_identity.name
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.tags
}
