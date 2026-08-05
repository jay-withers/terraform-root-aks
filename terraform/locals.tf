locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })

  # The vended landing zone — looked up, not created (see data.tf). Everything here
  # deploys into it, and takes its region from it.
  resource_group_name = data.azurerm_resource_group.landing_zone.name
  resource_group_id   = data.azurerm_resource_group.landing_zone.id
  location            = data.azurerm_resource_group.landing_zone.location

  # Every name the Azure naming module produces ends in this — rg-main-dev,
  # aks-main-dev, vnet-main-dev.
  #
  # Resources whose name also has to carry a role take the module's name and append
  # it: nsg-main-dev-nodes, vm-main-dev-jumpbox, kv-main-dev-jumpbox. That keeps the
  # role last, which is the shape the module would produce given
  # suffix = [workload, environment, role] — so the names stay put if these ever move
  # onto their own module instances, and everything in an environment shares one
  # <type>-<workload>-<environment> prefix.
  #
  # This local is for the one name the module cannot generate correctly: Bastion.
  name_suffix = "${var.workload_name}-${var.environment}"

  # The private endpoint subnet and its NSG follow the vault; nothing else takes one.
  privatelink_enabled = var.workload_key_vault_enabled

  # Every subnet in the cluster VNet, as the AVM virtual network module takes them.
  #
  # Subnet names stay role-only, unlike the <type>-<workload>-<environment>-<role>
  # form the rest use: they are scoped inside a VNet that already carries both, and
  # renaming one is a cluster rebuild — node pools take vnet_subnet_id at create time
  # only, and the destroy fails while pools are still attached.
  #
  # default_outbound_access_enabled and private_endpoint_network_policies are set
  # explicitly rather than left to the module's defaults, and both are create-time only
  # on Azure's side — getting either wrong is a subnet rebuild, which for the node
  # subnet means a cluster rebuild. The jump box genuinely needs outbound access: no NAT
  # gateway, no load balancer, and cloud-init pulls its tooling from the internet on
  # first boot. Nodes reach the internet through the AKS-managed load balancer, so true
  # is belt-and-braces there rather than required.
  subnets = merge(
    {
      # Nodes only. Azure CNI Overlay keeps pods on var.pod_cidr rather than on VNet
      # addresses, so this sizes to the node count, not the pod count.
      nodes = {
        name                              = "snet-nodes"
        address_prefix                    = var.node_subnet_address_prefix
        default_outbound_access_enabled   = true
        private_endpoint_network_policies = "Disabled"
        network_security_group            = { id = module.nsg_nodes.resource_id }
        role_assignments                  = local.subnet_role_assignments
      }

      # API server VNet integration projects the API server into this subnet behind
      # an internal load balancer instead of a Private Link private endpoint — no
      # per-hour endpoint charge, no data-processing charge, and node-to-API traffic
      # stays inside the VNet. The subnet must be /28 or larger, must be delegated to
      # Microsoft.ContainerService/managedClusters, and must hold nothing else.
      api_server = {
        name                              = "snet-apiserver"
        address_prefix                    = var.api_server_subnet_address_prefix
        default_outbound_access_enabled   = true
        private_endpoint_network_policies = "Disabled"
        network_security_group            = { id = module.nsg_api_server.resource_id }
        role_assignments                  = local.subnet_role_assignments

        delegations = [{
          name               = "aks-apiserver"
          service_delegation = { name = "Microsoft.ContainerService/managedClusters" }
        }]
      }
    },
    var.jumpbox_enabled ? {
      jumpbox = {
        name                              = "snet-jumpbox"
        address_prefix                    = var.jumpbox_subnet_address_prefix
        default_outbound_access_enabled   = true
        private_endpoint_network_policies = "Disabled"
        network_security_group            = { id = module.nsg_jumpbox[0].resource_id }
      }
    } : {},
    local.privatelink_enabled ? {
      privatelink = {
        name                              = "snet-privatelink"
        address_prefix                    = var.privatelink_subnet_address_prefix
        private_endpoint_network_policies = "Disabled"
        network_security_group            = { id = module.nsg_privatelink[0].resource_id }

        # A private endpoint originates nothing.
        default_outbound_access_enabled = false
      }
    } : {},
  )

  # Scoped to the subnets the cluster runs in, not the whole VNet. The jump box and
  # private link subnets are deliberately excluded.
  subnet_role_assignments = {
    aks = {
      role_definition_id_or_name = "Network Contributor"
      principal_id               = module.aks_identity.principal_id
    }
  }

  # one() over a filtered map yields null rather than failing on an absent key.
  jumpbox_subnet_id     = one([for key, subnet in module.vnet.subnets : subnet.resource_id if key == "jumpbox"])
  privatelink_subnet_id = one([for key, subnet in module.vnet.subnets : subnet.resource_id if key == "privatelink"])

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
    subnet_id                          = module.vnet.subnets["api_server"].resource_id

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

  # --- jump box -------------------------------------------------------------
  # Object inputs for the AVM virtual machine and Key Vault modules. Named locals
  # rather than inline blocks so tests can assert on them — a resource inside a child
  # module is not reachable from a `run` block.

  # Bastion Developer deploys into this VNet on connect rather than into a
  # dedicated AzureBastionSubnet, so its traffic arrives with a VirtualNetwork
  # source. Azure's default rules would already permit this; the rule is spelled
  # out so that the reason port 22 must stay reachable is visible to whoever
  # tightens these next. Note the source is the VNet, never the internet.
  jumpbox_nsg_rules = {
    bastion_ssh_inbound = {
      name                       = "AllowBastionSshInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
  }

  # No public IP: Bastion is the only way to reach this.
  jumpbox_network_interfaces = {
    internal = {
      name = "${module.naming.network_interface.name}-jumpbox"

      ip_configurations = {
        internal = {
          name                          = "internal"
          private_ip_subnet_resource_id = local.jumpbox_subnet_id
          private_ip_address_allocation = "Dynamic"
          create_public_ip_address      = false
        }
      }
    }
  }

  # The account operators sign in as. Passwords stay off — a password on a shared
  # admin box is a credential that gets written down and never rotated.
  #
  # The key comes from tls_private_key rather than from the module's own
  # key_vault_configuration, because that path always stamps an expiry on the secret
  # (45 days by default, no way to omit it) and Key Vault refuses to serve an expired
  # secret. On the only route into a private cluster that is a timed lock-out.
  jumpbox_account_credentials = {
    password_authentication_disabled = true

    admin_credentials = {
      username = "azureuser"

      # Splat, not an index: evaluated even when jumpbox_enabled is false.
      ssh_keys                           = tls_private_key.jumpbox_admin[*].public_key_openssh
      generate_admin_password_or_ssh_key = false
    }
  }

  # The extension below binds SSH to Entra ID, which needs an identity on the VM.
  jumpbox_managed_identities = {
    system_assigned = true
  }

  # Dormant on the Developer SKU — portal Entra ID auth needs Basic or above — but
  # kept because it costs nothing and makes "upgrade Bastion to Basic" the one change
  # that retires the shared Key Vault key. Also enables `az ssh vm`.
  #
  # Operators still need "Virtual Machine Administrator Login" on the VM and an AKS
  # role such as "Azure Kubernetes Service RBAC Reader" on the cluster; reaching the
  # box is not the same as being allowed to do anything once kubectl authenticates.
  jumpbox_extensions = {
    entra_login = {
      name                       = "AADSSHLoginForLinux"
      publisher                  = "Microsoft.Azure.ActiveDirectory"
      type                       = "AADSSHLoginForLinux"
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
      tags                       = local.tags
    }
  }

  # Named like every other role-carrying resource here, which drops the naming
  # module's random component. The trade: a vault name is a global DNS label, so
  # "kv-main-dev-jumpbox" fails at apply with VaultAlreadyExists if any tenant
  # anywhere claimed it first. A distinctive workload_name is the mitigation. The
  # roles also cost 8 of 24 characters, which is what caps workload_name at 9.
  jumpbox_key_vault_name  = "${module.naming.key_vault.name}-jumpbox"
  workload_key_vault_name = "${module.naming.key_vault.name}-secrets"

  # Select this secret in the Bastion connection pane, authentication type "SSH
  # Private Key from Azure Key Vault", username "azureuser". Written by Terraform
  # rather than pasted through the portal: the portal's editor mangles PEM line
  # endings and yields a key that fails to authenticate with no useful error.
  #
  # Rotation is not a re-apply — tls_private_key regenerates only when replaced:
  #   terraform apply -replace='tls_private_key.jumpbox_admin[0]'
  jumpbox_key_vault_secrets = {
    ssh_private_key = {
      name            = "jumpbox-ssh-private-key"
      content_type    = "application/x-pem-file"
      expiration_date = var.jumpbox_key_expiry_date
      tags            = local.tags
    }
  }

  # Owner grants no data-plane rights in RBAC mode, and Terraform needs them to write
  # the secret. This covers whoever runs Terraform; anyone else signing in needs "Key
  # Vault Secrets User" here, on top of the Reader roles Bastion requires.
  jumpbox_key_vault_role_assignments = {
    deployer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  # Named by hand rather than from the naming module on purpose: that module's
  # bastion_host slug is "snap", not "bas" — module.naming.bastion_host.name
  # returns "snap-main-dev". "bas" is the CAF abbreviation, so this stays literal.
  bastion_name = "bas-${local.name_suffix}"

  # The Developer SKU is free and needs no AzureBastionSubnet — it runs on shared
  # infrastructure that attaches to the VNet on connect. The trade-offs: browser
  # sessions only (native client and file transfer are Standard SKU), one VM at a
  # time, and it is not offered in every region.
  bastion_sku = "Developer"

  # --- workload Key Vault ---------------------------------------------------

  # Closing the public endpoint is what shuts the door; the ACL governs anything that
  # arrives anyway. bypass stays "None" — "AzureServices" would admit any
  # Microsoft-operated service to a vault designed to be reached from one VNet.
  workload_key_vault_network = {
    public_network_access_enabled = false

    network_acls = {
      bypass         = "None"
      default_action = "Deny"
    }
  }

  workload_key_vault_private_endpoints = {
    vault = {
      name               = "pep-${local.workload_key_vault_name}"
      subnet_resource_id = local.privatelink_subnet_id

      # Creates the A record in privatelink.vaultcore.azure.net and keeps it in step.
      # The zone is the hub's; this cluster only links its VNet to it.
      private_dns_zone_resource_ids = data.azurerm_private_dns_zone.key_vault[*].id
    }
  }

  # Note that "Key Vault Secrets Officer" alone is not enough to write here: the data
  # plane is only reachable over the private endpoint. var.workload_key_vault_secrets_users
  # is where workload identities go, keyed by index so the map stays known at plan time
  # even when the principal IDs are not.
  workload_key_vault_role_assignments = merge(
    {
      deployer = {
        role_definition_id_or_name = "Key Vault Secrets Officer"
        principal_id               = data.azurerm_client_config.current.object_id
      }
    },
    {
      for index, principal_id in var.workload_key_vault_secrets_users :
      "secrets_user_${index}" => {
        role_definition_id_or_name = "Key Vault Secrets User"
        principal_id               = principal_id
      }
    },
  )

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
