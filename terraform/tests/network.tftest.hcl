# The private posture and the egress path are both create-time only — a
# regression here is not a drifted setting, it is a cluster rebuild. These pin
# the parts that would otherwise be quiet to lose.

mock_provider "azurerm" {
  # azurerm_key_vault validates tenant_id as a UUID at plan time; the provider
  # mock otherwise generates a random string.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
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

  assert {
    condition     = one(azurerm_subnet.api_server.delegation).service_delegation[0].name == "Microsoft.ContainerService/managedClusters"
    error_message = "VNet integration requires the API server subnet delegated to Microsoft.ContainerService/managedClusters"
  }
}

run "rejects_api_server_subnet_smaller_than_a_28" {
  command = plan

  variables {
    api_server_subnet_address_prefix = "10.0.4.0/29"
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
    condition     = azurerm_subnet.nodes.address_prefixes == tolist([var.node_subnet_address_prefix])
    error_message = "the node subnet must use the configured prefix"
  }
}

run "cluster_identity_can_join_both_subnets" {
  command = plan

  # Scopes are unknown until apply; referencing both assignments at all is what
  # catches one being dropped, and the role name is what catches it being
  # widened or weakened.
  assert {
    condition     = azurerm_role_assignment.aks_nodes_subnet.role_definition_name == "Network Contributor"
    error_message = "the cluster identity must be able to join the node subnet"
  }

  assert {
    condition     = azurerm_role_assignment.aks_api_server_subnet.role_definition_name == "Network Contributor"
    error_message = "the cluster identity must be able to join the API server subnet"
  }
}
