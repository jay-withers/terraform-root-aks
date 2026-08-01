# A private cluster has to bring its own VNet — AKS will only place a private
# API server and its node pools in a network it does not own. Note that both
# api_server_access_profile.enable_private_cluster and
# network_profile.outbound_type are create-time only: changing either replaces
# the cluster.

resource "azurerm_virtual_network" "this" {
  name                = module.naming.virtual_network.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

# Nodes only. Azure CNI Overlay keeps pods on var.pod_cidr rather than on VNet
# addresses, so this sizes to the node count, not the pod count.
#
# The subnets are the one set of names here that stay role-only, rather than the
# <type>-<workload>-<environment>-<role> form the rest use. They are scoped inside
# a VNet that already carries the workload and environment, and renaming one is not
# a cheap change: the node pools
# take vnet_subnet_id at create time only, so a new subnet name replaces the
# cluster — and the destroy fails while node pools are still attached, so it is a
# tear-down and rebuild rather than a rename.
resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_address_prefix]
}

# API server VNet integration projects the API server into this subnet behind an
# internal load balancer instead of a Private Link private endpoint — no
# per-hour endpoint charge, no data-processing charge, and node-to-API traffic
# stays inside the VNet. The subnet must be /28 or larger, must be delegated to
# Microsoft.ContainerService/managedClusters, and must hold nothing else.
resource "azurerm_subnet" "api_server" {
  name                 = "snet-apiserver"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.api_server_subnet_address_prefix]

  delegation {
    name = "aks-apiserver"

    service_delegation {
      name    = "Microsoft.ContainerService/managedClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  # AKS re-writes the delegation's action list as it enables integration, which
  # would otherwise show as drift on every plan. The delegation above still
  # applies at create time.
  lifecycle {
    ignore_changes = [delegation]
  }
}

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
resource "azurerm_network_security_group" "nodes" {
  name                = "${module.naming.network_security_group.name}-nodes"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

resource "azurerm_network_security_group" "api_server" {
  name                = "${module.naming.network_security_group.name}-apiserver"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "api_server" {
  subnet_id                 = azurerm_subnet.api_server.id
  network_security_group_id = azurerm_network_security_group.api_server.id
}

# BYO networking rules out a system-assigned identity: the cluster's rights on
# these subnets have to exist before the cluster does, and a system-assigned
# identity is not created until then.
resource "azurerm_user_assigned_identity" "aks" {
  name                = module.naming.user_assigned_identity.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# Scoped to the two subnets rather than the whole VNet — the cluster needs to
# join and manage these, nothing else on the network.
resource "azurerm_role_assignment" "aks_nodes_subnet" {
  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_api_server_subnet" {
  scope                = azurerm_subnet.api_server.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}
