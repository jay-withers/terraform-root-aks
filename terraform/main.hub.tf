# Peering to the hub. Both halves are created here because peering is a write on
# each VNet independently — one side alone leaves the link in Initiated, never
# Connected. The identity this runs as is granted a custom five-action peering role on
# the hub VNet by the landingzones component precisely so this module can create the
# hub half; it deliberately has no broader rights there and cannot touch the hub's
# subnets or NSGs.
#
# Names are directional so the pair reads unambiguously in the portal.
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${local.name_suffix}-to-${var.hub_workload}"
  resource_group_name       = local.resource_group_name
  virtual_network_name      = module.vnet.name
  remote_virtual_network_id = data.azurerm_virtual_network.hub.id

  allow_virtual_network_access = true

  # The spoke does not route for anything else, and enabling gateway transit or
  # forwarded traffic here would only matter with a gateway or appliance in the hub
  # that this cluster is not configured to use — outbound_type is loadBalancer.
  allow_forwarded_traffic = false
  allow_gateway_transit   = false
  use_remote_gateways     = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-${var.hub_workload}-to-${local.name_suffix}"
  resource_group_name       = module.hub_naming.resource_group.name
  virtual_network_name      = data.azurerm_virtual_network.hub.name
  remote_virtual_network_id = module.vnet.resource_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
