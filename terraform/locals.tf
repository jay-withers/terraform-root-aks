locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })

  # admin_group_object_ids is omitted deliberately: AKS binds those groups
  # straight to cluster-admin, which no Azure role assignment can revoke. Grant
  # admin with the "Azure Kubernetes Service RBAC Cluster Admin" role instead.
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
    tenant_id         = data.azurerm_client_config.current.tenant_id
  }

  # kube-dns takes the tenth address of the service range. Deriving it rather
  # than taking a second input stops the two drifting apart, which AKS rejects.
  dns_service_ip = cidrhost(var.service_cidr, 10)

  # No public API endpoint: the API server is reachable only over the private
  # network, or through `az aks command invoke`.
  #
  # enable_vnet_integration puts the API server behind an internal load balancer
  # in snet-apiserver instead of a Private Link private endpoint — cheaper, and
  # node-to-API traffic never leaves the VNet.
  #
  # The public FQDN is off. It would be a publicly *resolvable* name pointing at
  # the private endpoint — no access on its own, but it does publish the API
  # server's private address. It is only worth that trade for clients outside the
  # VNet, which would otherwise need an Azure DNS Private Resolver or a forwarder
  # to resolve the private zone. The jump box is inside the VNet and resolves it
  # natively through Azure DNS, so nothing here needs it. Turn it on if a VPN or
  # peered network is added later and you would rather not pay for a resolver.
  #
  # disable_run_command is deliberately left off: `az aks command invoke` tunnels
  # kubectl through the ARM control plane, which is the only zero-cost way into a
  # private cluster from a GitHub-hosted runner. It authenticates through Entra
  # ID and Azure RBAC like any other client. Set it if that control-plane path is
  # itself unacceptable, but have another route in place first.
  api_server_access_profile = {
    enable_private_cluster             = true
    enable_private_cluster_public_fqdn = false
    enable_vnet_integration            = true
    subnet_id                          = azurerm_subnet.api_server.id

    # AKS creates and manages the zone in the node resource group. Under VNet
    # integration it is named private.<region>.azmk8s.io, not the privatelink.*
    # form a Private Link cluster gets. A BYO zone is only worth the extra
    # identity and role assignments if it has to be linked into a hub VNet.
    private_dns_zone = "system"
  }

  # Overlay keeps pods off VNet addresses, so the node subnet stays small and the
  # VNet cannot be exhausted by pod density. Cilium is the current AKS dataplane
  # default and carries no extra cost over kube-proxy plus Azure network policy.
  #
  # outbound_type is pinned to loadBalancer — the cheap egress path. Moving to
  # userDefinedRouting to force traffic through an Azure Firewall costs
  # substantially more per month than the rest of this cluster's networking
  # combined, and cannot be changed after creation.
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_dataplane   = "cilium"
    network_policy      = "cilium"
    outbound_type       = "loadBalancer"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = local.dns_service_ip
  }

  # Tooling for the jump box. Installed at first boot rather than baked into a
  # custom image — there is no image pipeline in this repo, and rebuilding the
  # box is how it gets updated.
  #
  # `az aks install-cli` brings kubectl and kubelogin; kubelogin is what makes
  # the kubeconfig work at all here, since local accounts are disabled and the
  # cluster authenticates through Entra ID.
  jumpbox_cloud_init = <<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - curl
      - jq
      - git
    runcmd:
      - [ bash, -c, "curl -sL https://aka.ms/InstallAzureCLIDeb | bash" ]
      - [ bash, -c, "az aks install-cli" ]
      - [ bash, -c, "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" ]
  CLOUDINIT

  # These names are reserved: AKS binds a maintenance window to an auto-upgrade
  # channel by name alone, and any other name gates nothing.
  maintenance_configuration = merge(
    {
      node_os = {
        name = "aksManagedNodeOSUpgradeSchedule"
        maintenance_window = {
          duration_hours = var.node_os_maintenance_window.duration_hours
          start_time     = var.node_os_maintenance_window.start_time
          utc_offset     = var.node_os_maintenance_window.utc_offset
          schedule = {
            daily = {
              interval_days = var.node_os_maintenance_window.interval_days
            }
          }
        }
      }
    },
    # Inert unless the Kubernetes auto-upgrade channel is on.
    var.kubernetes_upgrade_channel == "none" ? {} : {
      cluster = {
        name = "aksManagedAutoUpgradeSchedule"
        maintenance_window = {
          duration_hours = var.cluster_maintenance_window.duration_hours
          start_time     = var.cluster_maintenance_window.start_time
          utc_offset     = var.cluster_maintenance_window.utc_offset
          schedule = {
            weekly = {
              day_of_week    = var.cluster_maintenance_window.day_of_week
              interval_weeks = var.cluster_maintenance_window.interval_weeks
            }
          }
        }
      }
    }
  )
}
