# The jump box is the only route to the API server, so the properties that keep
# it both reachable and not-public are worth pinning.
#
# Everything here now lives inside an AVM module, and a resource inside a child module
# cannot be referenced from a `run` block — so these assert on the locals that
# configured it, or on a module output where one is known at plan time.

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
mock_provider "random" {}

run "jumpbox_has_no_public_ip" {
  command = plan

  # A public IP here would put an SSH port on the internet in front of the one box
  # that can reach the private cluster. The module both creates one on request and
  # attaches an existing one by ID, so both routes have to stay shut.
  assert {
    condition = alltrue(flatten([
      for interface in local.jumpbox_network_interfaces : [
        for config in interface.ip_configurations :
        config.create_public_ip_address == false &&
        !contains(keys(config), "public_ip_address_resource_id")
      ]
    ]))
    error_message = "the jump box must be reachable only through Bastion, never from the internet"
  }
}

run "jumpbox_does_not_accept_rdp_from_the_internet" {
  command = plan

  assert {
    condition = alltrue([
      for rule in local.jumpbox_nsg_rules :
      rule.source_address_prefix != "*" && rule.source_address_prefix != "Internet"
      if rule.direction == "Inbound" && rule.access == "Allow"
    ])
    error_message = "no inbound allow rule on the jump box may accept traffic from the internet"
  }

  # RDP is what Bastion Developer speaks to a Windows VM — cross-protocol
  # connections are a Standard SKU feature. An NSG still allowing only 22 would
  # leave the box unreachable through the one route it has.
  assert {
    condition = anytrue([
      for rule in local.jumpbox_nsg_rules :
      rule.destination_port_range == "3389"
      if rule.direction == "Inbound" && rule.access == "Allow"
    ])
    error_message = "Bastion reaches a Windows jump box over RDP, so 3389 must be allowed inbound from the VNet"
  }
}

run "sign_in_password_is_generated_not_chosen" {
  command = plan

  # Pinned because it is counter-intuitive and easy to "fix" wrongly: the flag is
  # Linux-only, Windows always has password authentication, and the AVM module
  # rejects the plan if it is set false alongside os_type "Windows".
  assert {
    condition     = local.jumpbox_account_credentials.password_authentication_disabled
    error_message = "password_authentication_disabled is a Linux-only flag and must stay true on Windows, whatever the VM actually does"
  }

  # The module's own generated password is vaulted with an expiry that cannot be
  # omitted. See local.jumpbox_account_credentials.
  assert {
    condition     = !local.jumpbox_account_credentials.admin_credentials.generate_admin_password_or_ssh_key
    error_message = "the sign-in password must be the one this module generates, so its Key Vault secret can be written without a forced expiry"
  }

  # Long enough that the password being the only sign-in path is not the weakness
  # it would otherwise be, and complex enough that Windows accepts it outright.
  assert {
    condition     = random_password.jumpbox_admin[0].length >= 24
    error_message = "the jump box password is the only credential into a private cluster; it must be generated long"
  }
}

run "entra_id_login_is_installed" {
  command = plan

  # Dormant on the Developer SKU, which cannot do Entra ID auth — kept so that
  # upgrading Bastion to Basic retires the Key Vault password immediately.
  assert {
    condition     = local.jumpbox_extensions["entra_login"].type == "AADLoginForWindows"
    error_message = "the Entra ID login extension must stay installed, so a Bastion SKU upgrade is all that is needed to drop the shared password"
  }

  assert {
    condition     = local.jumpbox_managed_identities.system_assigned
    error_message = "the Entra ID login extension requires a managed identity on the VM"
  }
}

run "bootstrap_installs_the_tools_the_cluster_needs" {
  command = plan

  # Windows never executes custom_data, so the tooling install is an extension.
  # kubelogin is the load-bearing one: local accounts are disabled and Azure RBAC
  # is on, so kubectl cannot authenticate to this cluster without it.
  assert {
    condition     = strcontains(local.jumpbox_bootstrap_script, "kubelogin.exe")
    error_message = "the bootstrap must install kubelogin — with disable_local_accounts, kubectl cannot reach this cluster without it"
  }

  # Downloaded straight from dl.k8s.io rather than via "az aks install-cli", the
  # obvious route, which does not work on this image: it fetches through
  # azure-cli's bundled Python certificate store and fails TLS verification.
  assert {
    condition     = strcontains(local.jumpbox_bootstrap_script, "dl.k8s.io/release")
    error_message = "kubectl must come straight from dl.k8s.io; az aks install-cli fails TLS verification against it on this image"
  }

  assert {
    condition     = local.jumpbox_extensions["bootstrap"].type == "CustomScriptExtension"
    error_message = "the tooling install must run as an extension; Windows writes custom_data to disk and never runs it"
  }
}

run "sign_in_password_is_reachable" {
  command = plan

  # The Developer SKU cannot authenticate with Entra ID, so this password is the
  # only way in. If it is not in the vault, the jump box is unreachable.
  assert {
    condition     = local.jumpbox_key_vault_secrets["admin_password"].name == "jumpbox-admin-password"
    error_message = "the sign-in password must be stored in Key Vault; Bastion Developer has no other usable authentication method here"
  }

  # Key Vault refuses to serve an expired secret, and this one opens the only door
  # into the cluster. Opt in via var.jumpbox_secret_expiry_date once a rotation
  # process exists to meet the date.
  assert {
    condition     = local.jumpbox_key_vault_secrets["admin_password"].expiration_date == null
    error_message = "the sign-in password secret must not expire by default — an unwatched expiry locks everyone out of a private cluster"
  }
}

run "computer_name_fits_the_windows_limit" {
  command = plan

  variables {
    workload_name = "platform"
    environment   = "prd"
  }

  # Windows rejects a computer name over 15 characters rather than truncating it,
  # and the failure is at create. The role-suffixed resource name is longer than
  # that at every workload_name, so the two must stay separate values.
  assert {
    condition     = length(local.jumpbox_computer_name) <= 15
    error_message = "the Windows computer name must be 15 characters or fewer at the workload_name cap"
  }
}

run "key_vault_is_rbac_governed" {
  command = plan

  # The vault is publicly reachable by necessity, so RBAC is the only guard. The AVM
  # module uses RBAC unless legacy access policies are enabled, which nothing here
  # does; the data-plane grant is what is worth pinning, since Owner does not confer
  # it and the apply that writes the key fails without it.
  assert {
    condition     = local.jumpbox_key_vault_role_assignments["deployer"].role_definition_id_or_name == "Key Vault Secrets Officer"
    error_message = "Terraform needs data-plane rights to write the key; Owner does not grant them in RBAC mode"
  }
}

run "key_vault_is_open_by_default" {
  command = plan

  # null, not a Deny with an empty rule set. The AVM module's own default is a
  # default-deny firewall, so anything other than null here would lock out the
  # deploying identity that has to write the password over the data plane — on the
  # very first apply, before anyone could correct it.
  assert {
    condition     = local.jumpbox_key_vault_network_acls == null
    error_message = "with no allowed IP ranges the vault must carry no firewall at all; a default-deny would shut out Terraform itself"
  }

  # The public endpoint itself is a literal in main.jumpbox.tf rather than a local,
  # and the vault resource lives inside the AVM module where a run block cannot
  # reach it — so there is nothing here to assert it against. It has to stay on:
  # this vault has no private endpoint, so disabling it denies the operator the
  # password too. The allow list is what narrows access, not the endpoint switch.
  assert {
    condition     = length(module.jumpbox_key_vault) == 1
    error_message = "the jump box vault must exist for the allow list to have anything to govern"
  }
}

run "allowed_ip_ranges_switch_the_vault_to_default_deny" {
  command = plan

  variables {
    jumpbox_key_vault_allowed_ip_ranges = ["203.0.113.4", "198.51.100.0/24"]
  }

  assert {
    condition     = local.jumpbox_key_vault_network_acls.default_action == "Deny"
    error_message = "setting an allow list must flip the vault to default-deny; otherwise the list admits nobody extra and excludes nobody"
  }

  # "AzureServices" would readmit every Microsoft-operated service to a vault whose
  # point is now a short list of known addresses.
  assert {
    condition     = local.jumpbox_key_vault_network_acls.bypass == "None"
    error_message = "the trusted-services bypass must stay off; it would undo the allow list for a large set of callers"
  }

  assert {
    condition     = local.jumpbox_key_vault_network_acls.ip_rules == tolist(["203.0.113.4", "198.51.100.0/24"])
    error_message = "the configured ranges must reach the vault firewall unmodified"
  }
}

run "rejects_private_ip_ranges_the_vault_firewall_cannot_hold" {
  command = plan

  # Azure rejects RFC1918 ranges in Key Vault IP rules. Caught here because the
  # failure otherwise arrives at apply, against a vault that may already exist.
  variables {
    jumpbox_key_vault_allowed_ip_ranges = ["10.1.5.0/28"]
  }

  expect_failures = [var.jumpbox_key_vault_allowed_ip_ranges]
}

run "rejects_an_ip_range_that_is_not_ipv4" {
  command = plan

  # Key Vault IP rules are IPv4-only.
  variables {
    jumpbox_key_vault_allowed_ip_ranges = ["2001:db8::/32"]
  }

  expect_failures = [var.jumpbox_key_vault_allowed_ip_ranges]
}

run "bastion_uses_the_free_developer_sku" {
  command = plan

  assert {
    condition     = local.bastion_sku == "Developer"
    error_message = "Bastion must stay on the Developer SKU; Basic and above are billed hourly from deployment"
  }
}

run "jumpbox_can_be_turned_off_entirely" {
  command = plan

  variables {
    jumpbox_enabled = false
  }

  assert {
    condition     = length(module.jumpbox) == 0
    error_message = "jumpbox_enabled = false must create no VM"
  }

  # Bastion fronts only the jump box, so it must not outlive it and keep billing
  # or dangle against nothing.
  assert {
    condition     = length(module.bastion) == 0
    error_message = "Bastion must not be created when there is no jump box to reach"
  }

  assert {
    condition     = !contains(keys(local.subnets), "jumpbox")
    error_message = "jumpbox_enabled = false must leave no orphaned subnet"
  }

  assert {
    condition     = length(module.nsg_jumpbox) == 0
    error_message = "jumpbox_enabled = false must leave no orphaned network security group"
  }

  # The vault exists only to hold the sign-in key for a VM that is now gone.
  assert {
    condition     = length(module.jumpbox_key_vault) == 0
    error_message = "jumpbox_enabled = false must leave no vault holding a key to a VM that does not exist"
  }
}

run "bastion_can_be_disabled_where_the_region_lacks_it" {
  command = plan

  variables {
    bastion_enabled = false
  }

  assert {
    condition     = length(module.bastion) == 0
    error_message = "bastion_enabled = false must create no Bastion host"
  }

  assert {
    condition     = length(module.jumpbox) == 1
    error_message = "disabling Bastion must leave the jump box in place — the portal can deploy Bastion Developer on demand"
  }
}
