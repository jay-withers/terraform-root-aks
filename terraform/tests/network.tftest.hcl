# The private posture and the egress path are both create-time only — a
# regression here is not a drifted setting, it is a cluster rebuild. These pin
# the parts that would otherwise be quiet to lose.

mock_provider "azurerm" {
  # The landing zone resource group, the hub VNet and the hub's private DNS zone are
  # looked up, not created (see data.tf). Their IDs are fed to AVM modules that
  # validate the resource ID format; the provider mock otherwise generates a random
  # string. Names here are fixed rather than derived — assertions about derived names
  # use module.naming, which is real.
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-aks-dev"
      name     = "rg-aks-dev"
      location = "westeurope"
    }
  }

  mock_data "azurerm_virtual_network" {
    defaults = {
      id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub-dev/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev"
      name = "vnet-hub-dev"
    }
  }

  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub-dev/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      name = "privatelink.vaultcore.azure.net"
    }
  }

  # azurerm_key_vault validates tenant_id as a UUID at plan time; the provider
  # mock otherwise generates a random string.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

# The AVM modules reach Azure through azapi, and build resource IDs from the
# client config — an unmocked subscription_id fails ID validation at plan time.
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "22222222-2222-2222-2222-222222222222"
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
    }
  }
}

run "api_server_is_private" {
  command = plan

  assert {
    condition     = local.api_server_access_profile.enable_private_cluster
    error_message = "the API server must have no public endpoint"
  }

  # Nothing outside the VNet needs to resolve the API server — the jump box is
  # inside it — so the private address stays out of public DNS.
  assert {
    condition     = !local.api_server_access_profile.enable_private_cluster_public_fqdn
    error_message = "the public FQDN publishes the API server's private address and buys nothing while access is from inside the VNet"
  }

  assert {
    condition     = local.api_server_access_profile.enable_vnet_integration
    error_message = "VNet integration must be on — it is what keeps the API server off a billed Private Link endpoint"
  }

  # The subnet ID itself is unknown until apply, so this pins the DNS mode
  # instead: "none" would leave the private FQDN unresolvable with no zone to
  # fall back on.
  assert {
    condition     = local.api_server_access_profile.private_dns_zone == "system"
    error_message = "the private FQDN needs an AKS-managed private DNS zone unless a BYO zone is wired up"
  }
}

run "api_server_subnet_is_delegated_to_aks" {
  command = plan

  # The subnets are created inside the AVM virtual network module, so the map that
  # configures them is what a test can reach. See local.subnets.
  assert {
    condition     = one(local.subnets["api_server"].delegations).service_delegation.name == "Microsoft.ContainerService/managedClusters"
    error_message = "VNet integration requires the API server subnet delegated to Microsoft.ContainerService/managedClusters"
  }
}

run "rejects_api_server_subnet_smaller_than_a_28" {
  command = plan

  variables {
    api_server_subnet_address_prefix = "10.1.4.0/29"
  }

  expect_failures = [var.api_server_subnet_address_prefix]
}

run "egress_stays_on_the_load_balancer" {
  command = plan

  # userDefinedRouting implies an appliance — typically an Azure Firewall, which
  # costs more per month than everything else here combined.
  assert {
    condition     = local.network_profile.outbound_type == "loadBalancer"
    error_message = "outbound_type must stay loadBalancer; changing it is a cluster rebuild and a large cost increase"
  }
}

run "pods_do_not_consume_vnet_addresses" {
  command = plan

  assert {
    condition     = local.network_profile.network_plugin_mode == "overlay"
    error_message = "overlay mode keeps pods off VNet addresses, which is what allows the small node subnet"
  }

  assert {
    condition     = local.network_profile.pod_cidr == var.pod_cidr
    error_message = "pods must be allocated from the overlay pod CIDR"
  }
}

run "dns_service_ip_is_derived_from_the_service_cidr" {
  command = plan

  variables {
    service_cidr = "172.20.0.0/16"
  }

  assert {
    condition     = local.network_profile.dns_service_ip == "172.20.0.10"
    error_message = "the kube-dns service IP must track service_cidr; AKS rejects one outside the other"
  }
}

run "every_pool_lands_in_the_node_subnet" {
  command = plan

  # A pool left without a subnet silently falls back to an AKS-managed VNet,
  # which would sit outside the private network entirely.
  assert {
    condition     = local.subnets["nodes"].address_prefix == var.node_subnet_address_prefix
    error_message = "the node subnet must use the configured prefix"
  }
}

run "cluster_identity_can_join_both_subnets" {
  command = plan

  # The grants are properties of the subnets rather than resources of their own.
  # Asserting on each subnet's map is what catches one being dropped, and the role
  # name is what catches it being widened or weakened.
  assert {
    condition     = local.subnets["nodes"].role_assignments["aks"].role_definition_id_or_name == "Network Contributor"
    error_message = "the cluster identity must be able to join the node subnet"
  }

  assert {
    condition     = local.subnets["api_server"].role_assignments["aks"].role_definition_id_or_name == "Network Contributor"
    error_message = "the cluster identity must be able to join the API server subnet"
  }

  # Reaching the jump box and the private endpoints is not the cluster's business.
  assert {
    condition = alltrue([
      !contains(keys(local.subnets["jumpbox"]), "role_assignments"),
      !contains(keys(local.subnets["privatelink"]), "role_assignments"),
    ])
    error_message = "the cluster identity must not hold rights over the jump box or private link subnets"
  }
}

run "the_jump_box_subnet_can_reach_the_internet" {
  command = plan

  # Not a nicety: the jump box has no NAT gateway and no load balancer, and its
  # cloud-init installs the Azure CLI, kubectl, helm and flux from the internet on
  # first boot. defaultOutboundAccess is create-time only, so getting this wrong is
  # a rebuild of the box, not a setting to correct.
  assert {
    condition     = local.subnets["jumpbox"].default_outbound_access_enabled
    error_message = "the jump box subnet needs default outbound access; nothing else gives it egress and cloud-init would fail"
  }

  # A private endpoint originates nothing.
  assert {
    condition     = !local.subnets["privatelink"].default_outbound_access_enabled
    error_message = "the private link subnet has no reason to reach the internet"
  }
}
