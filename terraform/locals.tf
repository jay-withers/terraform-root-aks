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
  # out so that the reason port 3389 must stay reachable is visible to whoever
  # tightens these next. Note the source is the VNet, never the internet.
  #
  # RDP, not SSH: Bastion Developer can reach a Windows VM over RDP and a Linux
  # VM over SSH, and neither the other way round — cross-protocol connections are
  # a Standard SKU feature.
  jumpbox_nsg_rules = {
    bastion_rdp_inbound = {
      name                       = "AllowBastionRdpInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
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

  # The Windows computer name, capped at 15 characters by NetBIOS and rejected
  # outright past it. The naming module already substrs its VM names to 15, so
  # taking its output unmodified is what keeps this valid at any workload_name —
  # appending a role the way every other resource here does would overflow it.
  jumpbox_computer_name = module.naming.windows_virtual_machine.name

  # The account operators sign in as. A password, against the Linux box's rule
  # that passwords stay off, because Windows leaves no alternative on this SKU:
  # there is no SSH-key equivalent, and Bastion Developer cannot do Entra ID.
  #
  # The mitigations for what that rule was guarding against — a credential written
  # down and never rotated — are that nobody chooses or types this password, it is
  # generated at 32 characters, it is read from Key Vault at connect time, and
  # rotating it is a single -replace. See random_password.jumpbox_admin.
  #
  # password_authentication_disabled stays true, and reads like the opposite of
  # what this block does. The flag is Linux-only — azurerm_windows_virtual_machine
  # has no way to turn password authentication off, so Windows always has it — and
  # the module validates that it is left at true for os_type "Windows". Setting it
  # false to match reality fails the plan.
  jumpbox_account_credentials = {
    password_authentication_disabled = true

    admin_credentials = {
      username = "azureuser"

      # Splat and one(), not an index: evaluated even when jumpbox_enabled is false.
      password                           = one(random_password.jumpbox_admin[*].result)
      generate_admin_password_or_ssh_key = false
    }
  }

  # The Entra ID extension below needs an identity on the VM.
  jumpbox_managed_identities = {
    system_assigned = true
  }

  # entra_login is dormant on the Developer SKU — portal Entra ID auth needs Basic
  # or above — but kept because it costs nothing and makes "upgrade Bastion to
  # Basic" the one change that retires the shared Key Vault password.
  #
  # Operators still need "Virtual Machine Administrator Login" on the VM and an AKS
  # role such as "Azure Kubernetes Service RBAC Reader" on the cluster; reaching the
  # box is not the same as being allowed to do anything once kubectl authenticates.
  #
  # bootstrap replaces what cloud-init did on the Linux box. It runs after
  # entra_login rather than alongside it: two extensions installing at once on a
  # 2-vCPU VM is where Custom Script times out.
  jumpbox_extensions = {
    entra_login = {
      name                       = "AADLoginForWindows"
      publisher                  = "Microsoft.Azure.ActiveDirectory"
      type                       = "AADLoginForWindows"
      type_handler_version       = "2.0"
      auto_upgrade_minor_version = true
      deploy_sequence            = 1
      tags                       = local.tags
    }

    bootstrap = {
      name                       = "CustomScriptExtension"
      publisher                  = "Microsoft.Compute"
      type                       = "CustomScriptExtension"
      type_handler_version       = "1.10"
      auto_upgrade_minor_version = true
      deploy_sequence            = 2
      provision_after_extensions = ["AADLoginForWindows"]
      tags                       = local.tags

      # Base64 round-trip rather than -EncodedCommand: that flag wants UTF-16LE,
      # which base64encode cannot produce. Decoding UTF-8 in the command itself
      # keeps the script readable below instead of collapsed onto one escaped line.
      settings = jsonencode({
        commandToExecute = join(" ", [
          "powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -Command",
          "\"iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${base64encode(local.jumpbox_bootstrap_script)}')))\"",
        ])
      })
    }
  }

  # Named like every other role-carrying resource here, which drops the naming
  # module's random component. The trade: a vault name is a global DNS label, so
  # "kv-main-dev-workload" fails at apply with VaultAlreadyExists if any tenant
  # anywhere claimed it first. A distinctive workload_name is the mitigation.
  #
  # "-workload" is the longer of the two roles at 9 characters, so it is the one
  # that sets the cap: "kv-" + workload_name + "-" + environment + "-workload"
  # reaches Key Vault's 24-character limit at a workload_name of 8. Renaming
  # either of these is a vault replacement, not a rename — Key Vault has no rename
  # — so the cap moves before the names do.
  jumpbox_key_vault_name  = "${module.naming.key_vault.name}-jump"
  workload_key_vault_name = "${module.naming.key_vault.name}-workload"

  # Read this secret from the vault and paste it into the Bastion connection pane
  # with username "azureuser". Bastion's "from Azure Key Vault" authentication type
  # is SSH-key only, so unlike the Linux box there is no path where Bastion fetches
  # the credential itself — the operator does, which is why "Key Vault Secrets
  # User" on this vault is now part of granting someone jump box access.
  #
  # Rotation is not a re-apply — random_password regenerates only when replaced:
  #   terraform apply -replace='random_password.jumpbox_admin[0]'
  # That changes the vault secret and the VM's admin password in the same apply.
  jumpbox_key_vault_secrets = {
    admin_password = {
      name            = "jumpbox-admin-password"
      content_type    = "text/plain"
      expiration_date = var.jumpbox_secret_expiry_date
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

  # The optional second guard in front of the sign-in password, on top of RBAC.
  #
  # This became possible only when the jump box went Windows. While the credential
  # was an SSH key, Bastion read it from the vault itself, from Microsoft's own
  # infrastructure outside this VNet and from no documented address range — an
  # allow list could not have included it. A password is read by an operator, from
  # somewhere known, so the vault no longer has to accept the whole internet.
  #
  # null, not a Deny-with-no-rules, when the list is empty: the AVM module's own
  # default is a default-deny firewall, and inheriting that would shut the vault to
  # everyone including Terraform. Empty therefore means "as before", not "locked".
  #
  # A private endpoint is still not the answer here, whatever this is set to. It
  # would put the password behind the network you need the password to reach — a
  # lock with the key inside. Public endpoint plus an allow list is the tightest
  # this vault can be and still be openable.
  jumpbox_key_vault_network_acls = length(var.jumpbox_key_vault_allowed_ip_ranges) == 0 ? null : {
    # "AzureServices" would readmit any Microsoft-operated service to a vault whose
    # whole point is now a short list of known addresses.
    bypass         = "None"
    default_action = "Deny"
    ip_rules       = var.jumpbox_key_vault_allowed_ip_ranges
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
  # What cloud-init did on the Linux box, as PowerShell for the Custom Script
  # extension. Same tools, resolved to their latest release at build time rather
  # than pinned — this box is rebuilt, not upgraded in place.
  #
  # Installed to Program Files and added to the machine PATH, so the tools are
  # there for every operator who signs in, not only the one the extension ran as.
  jumpbox_bootstrap_script = <<-POWERSHELL
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'  # Write-Progress is very slow over the extension's output capture.

    # IE Enhanced Security Configuration puts a click-through in front of every
    # navigation, which makes the portal — the reason this box is Windows —
    # unusable. Disabled for administrators only; the user-scope policy stays on.
    $escAdmin = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}'
    if (Test-Path $escAdmin) { Set-ItemProperty -Path $escAdmin -Name IsInstalled -Value 0 }

    # TLS 1.2 for every download below: Server 2022's PowerShell 5.1 still
    # defaults to SSL3/TLS1.0 and every one of these endpoints refuses it.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $tools = 'C:\Program Files\aks-tools'
    New-Item -ItemType Directory -Force -Path $tools | Out-Null

    # Azure CLI, via the MSI — there is no apt equivalent, and this is the only
    # supported Windows install path.
    # The x64 alias specifically: the plain "installazurecliwindows" URL still
    # serves the 32-bit build, which installs under "Program Files (x86)" and not
    # the root $env:ProgramFiles resolves to.
    $msi = Join-Path $env:TEMP 'azure-cli.msi'
    Invoke-WebRequest -Uri 'https://aka.ms/installazurecliwindowsx64' -OutFile $msi -UseBasicParsing
    $msiexec = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/i', "`"$msi`"", '/quiet', '/norestart'
    if ($msiexec.ExitCode -ne 0) { throw "Azure CLI MSI failed with exit code $($msiexec.ExitCode)" }
    Remove-Item $msi -Force

    # Confirmed present rather than assumed, across both Program Files roots — a
    # 32-bit MSI lands in the second. Failing here means the installer reported
    # success and put nothing down, which is worth stopping on.
    $azFound = @(
      (Join-Path $env:ProgramFiles 'Microsoft SDKs\Azure\CLI2\wbin\az.cmd'),
      # $${...} escapes the interpolation Terraform would otherwise read here.
      (Join-Path $${env:ProgramFiles(x86)} 'Microsoft SDKs\Azure\CLI2\wbin\az.cmd')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $azFound) { throw 'Azure CLI installed but az.cmd was not found under either Program Files root' }

    # kubectl and kubelogin, fetched directly rather than through
    # "az aks install-cli". That subcommand downloads them with azure-cli's own
    # bundled Python certificate store, which fails TLS verification against
    # dl.k8s.io on this image and reports only "SSL certificate verification
    # failed" (Azure/azure-cli#19305). Invoke-WebRequest uses the Windows
    # certificate store and reaches the identical endpoints without complaint.
    #
    # kubelogin is not optional here: the cluster has local accounts disabled and
    # Azure RBAC on, so every kubectl call needs it to exchange an Entra token for
    # cluster access.
    $kubectlVersion = (Invoke-WebRequest -Uri 'https://dl.k8s.io/release/stable.txt' -UseBasicParsing).Content.Trim()
    Invoke-WebRequest -Uri "https://dl.k8s.io/release/$kubectlVersion/bin/windows/amd64/kubectl.exe" -OutFile (Join-Path $tools 'kubectl.exe') -UseBasicParsing

    $kubeloginZip = Join-Path $env:TEMP 'kubelogin.zip'
    Invoke-WebRequest -Uri 'https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-win-amd64.zip' -OutFile $kubeloginZip -UseBasicParsing
    Expand-Archive -Path $kubeloginZip -DestinationPath $env:TEMP -Force
    Move-Item -Path (Join-Path $env:TEMP 'bin\windows_amd64\kubelogin.exe') -Destination $tools -Force
    Remove-Item $kubeloginZip -Force

    # helm and flux ship as zips with no installer. Latest release resolved from
    # the GitHub API, matching the get-helm-3 / fluxcd.io scripts the Linux box used.
    #
    # Non-fatal, unlike everything above. The unauthenticated GitHub API allows 60
    # calls an hour per source address and Azure egress addresses are shared, so
    # this can fail for reasons that have nothing to do with this cluster. These two
    # are conveniences; failing an apply — and leaving the VM in a failed extension
    # state — over someone else's rate limit is not a trade worth making. The
    # warning lands in the extension output, readable from the VM instance view.
    $headers = @{ 'User-Agent' = 'aks-jumpbox-bootstrap' }

    try {
      $helmVersion = (Invoke-RestMethod -Uri 'https://api.github.com/repos/helm/helm/releases/latest' -Headers $headers).tag_name
      $helmZip = Join-Path $env:TEMP 'helm.zip'
      Invoke-WebRequest -Uri "https://get.helm.sh/helm-$helmVersion-windows-amd64.zip" -OutFile $helmZip -UseBasicParsing
      Expand-Archive -Path $helmZip -DestinationPath $env:TEMP -Force
      Move-Item -Path (Join-Path $env:TEMP 'windows-amd64\helm.exe') -Destination $tools -Force
    } catch {
      Write-Warning "helm install skipped: $_"
    }

    try {
      $fluxTag = (Invoke-RestMethod -Uri 'https://api.github.com/repos/fluxcd/flux2/releases/latest' -Headers $headers).tag_name
      $fluxVersion = $fluxTag.TrimStart('v')
      $fluxZip = Join-Path $env:TEMP 'flux.zip'
      Invoke-WebRequest -Uri "https://github.com/fluxcd/flux2/releases/download/$fluxTag/flux_$($fluxVersion)_windows_amd64.zip" -OutFile $fluxZip -UseBasicParsing
      Expand-Archive -Path $fluxZip -DestinationPath $tools -Force
    } catch {
      Write-Warning "flux install skipped: $_"
    }

    # Machine scope, so a new RDP session picks these up without further setup.
    $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($path -notlike "*$tools*") {
      [Environment]::SetEnvironmentVariable('Path', "$path;$tools", 'Machine')
    }
  POWERSHELL

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
