locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })

  # Every name the Azure naming module produces ends in this — rg-main-dev,
  # aks-main-dev, vnet-main-dev.
  #
  # Resources whose name also has to carry a role take the module's name and append
  # it: nsg-main-dev-nodes, vm-main-dev-jumpbox. That keeps the role last, which is
  # the shape the module would produce given suffix = [workload, environment, role]
  # — so the names stay put if these ever move onto their own module instances, and
  # everything in an environment shares one <type>-<workload>-<environment> prefix.
  #
  # This local is for the one name the module cannot generate correctly: Bastion.
  name_suffix = "${var.workload_name}-${var.environment}"

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

  # The extension installs the Flux controllers; the configuration is what points
  # them at a repository. Without a URL there is nothing to point them at, so the
  # cluster gets Flux and no sync.
  flux_configuration_enabled = var.flux_enabled && var.flux_git_repository_url != null

  # The ARM API takes the git credentials base64-encoded. var.flux_git_credentials
  # takes them in their natural form — a PEM, a PAT, a known_hosts file — so the
  # encoding happens here rather than in every caller.
  flux_git_auth = {
    https_key_base64 = var.flux_git_credentials.https_key == null ? null : base64encode(var.flux_git_credentials.https_key)

    ssh_private_key_base64 = var.flux_git_credentials.ssh_private_key == null ? null : base64encode(var.flux_git_credentials.ssh_private_key)

    ssh_known_hosts_base64 = var.flux_git_credentials.ssh_known_hosts == null ? null : base64encode(var.flux_git_credentials.ssh_known_hosts)
  }

  # Tooling for the jump box. Installed at first boot rather than baked into a
  # custom image — there is no image pipeline in this repo, and rebuilding the
  # box is how it gets updated.
  #
  # So note what editing this costs: cloud-init is only read at first boot, which
  # makes custom_data create-time only, and any change here replaces the VM. The
  # Key Vault sign-in key and Bastion survive that, but anything an operator left
  # on the box does not. Expect a destroy/create in the plan, and use
  # `az aks command invoke` for cluster access while it rebuilds.
  #
  # `az aks install-cli` brings kubectl and kubelogin; kubelogin is what makes
  # the kubeconfig work at all here, since local accounts are disabled and the
  # cluster authenticates through Entra ID.
  #
  # The flux CLI is here to inspect and nudge the extension's controllers
  # (`flux get kustomizations`, `flux reconcile`) from inside the VNet. It must not
  # be used to `flux bootstrap` — Azure owns the install; see flux.tf.
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
      - [ bash, -c, "curl -fsSL https://fluxcd.io/install.sh | bash" ]
  CLOUDINIT

  # These names are reserved: AKS binds a maintenance window to an auto-upgrade
  # channel by name alone, and any other name gates nothing.
  #
  # start_date has to be sent, even though the API treats it as optional. Omit it
  # and AKS stores the date the configuration was created, while Terraform keeps
  # sending null — so every plan shows the same startDate -> null update, and every
  # apply is undone server-side. Any past date works; it only decides when the
  # window first becomes active, and these are meant to be active immediately.
  maintenance_configuration = merge(
    {
      node_os = {
        name = "aksManagedNodeOSUpgradeSchedule"
        maintenance_window = {
          duration_hours = var.node_os_maintenance_window.duration_hours
          start_time     = var.node_os_maintenance_window.start_time
          start_date     = var.node_os_maintenance_window.start_date
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
          start_date     = var.cluster_maintenance_window.start_date
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
