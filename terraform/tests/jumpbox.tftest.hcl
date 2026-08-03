# The jump box is the only route to the API server, so the properties that keep
# it both reachable and not-public are worth pinning.
#
# Everything here now lives inside an AVM module, and a resource inside a child module
# cannot be referenced from a `run` block — so these assert on the locals that
# configured it, or on a module output where one is known at plan time.

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
mock_provider "tls" {}

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

run "jumpbox_does_not_accept_ssh_from_the_internet" {
  command = plan

  assert {
    condition = alltrue([
      for rule in local.jumpbox_nsg_rules :
      rule.source_address_prefix != "*" && rule.source_address_prefix != "Internet"
      if rule.direction == "Inbound" && rule.access == "Allow"
    ])
    error_message = "no inbound allow rule on the jump box may accept traffic from the internet"
  }
}

run "passwords_are_disabled" {
  command = plan

  assert {
    condition     = local.jumpbox_account_credentials.password_authentication_disabled
    error_message = "password authentication must stay off; Entra ID is the login path"
  }

  # The module's own generated key is vaulted with an expiry that cannot be omitted.
  # See local.jumpbox_account_credentials.
  assert {
    condition     = !local.jumpbox_account_credentials.admin_credentials.generate_admin_password_or_ssh_key
    error_message = "the sign-in key must be the one this module generates, so its Key Vault secret can be written without a forced expiry"
  }
}

run "entra_id_login_is_installed" {
  command = plan

  # Dormant on the Developer SKU, which cannot do Entra ID auth — kept so that
  # upgrading Bastion to Basic retires the Key Vault key immediately.
  assert {
    condition     = local.jumpbox_extensions["entra_login"].type == "AADSSHLoginForLinux"
    error_message = "the Entra ID SSH login extension must stay installed, so a Bastion SKU upgrade is all that is needed to drop the shared key"
  }

  assert {
    condition     = local.jumpbox_managed_identities.system_assigned
    error_message = "the Entra ID login extension requires a managed identity on the VM"
  }
}

run "sign_in_key_is_reachable_and_rsa" {
  command = plan

  # The Developer SKU cannot authenticate with Entra ID, so this key is the only
  # way in. If it is not in the vault, the jump box is unreachable.
  assert {
    condition     = local.jumpbox_key_vault_secrets["ssh_private_key"].name == "jumpbox-ssh-private-key"
    error_message = "the sign-in key must be stored in Key Vault; Bastion Developer has no other usable authentication method here"
  }

  # The portal documents the private key as needing "-----BEGIN RSA PRIVATE
  # KEY-----" form, which ED25519 cannot produce.
  assert {
    condition     = tls_private_key.jumpbox_admin[0].algorithm == "RSA"
    error_message = "the sign-in key must be RSA — Bastion's Key Vault flow expects an RSA-format PEM"
  }

  # Key Vault refuses to serve an expired secret, and this one opens the only door
  # into the cluster. Opt in via var.jumpbox_key_expiry_date once a rotation process
  # exists to meet the date.
  assert {
    condition     = local.jumpbox_key_vault_secrets["ssh_private_key"].expiration_date == null
    error_message = "the sign-in key secret must not expire by default — an unwatched expiry locks everyone out of a private cluster"
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
