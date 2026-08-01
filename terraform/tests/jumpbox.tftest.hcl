# The jump box is the only route to the API server, so the properties that keep
# it both reachable and not-public are worth pinning.

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
mock_provider "tls" {}

run "jumpbox_has_no_public_ip" {
  command = plan

  # A public IP here would put an SSH port on the internet in front of the one
  # box that can reach the private cluster.
  assert {
    condition     = alltrue([for c in azurerm_network_interface.jumpbox[0].ip_configuration : c.public_ip_address_id == null])
    error_message = "the jump box must be reachable only through Bastion, never from the internet"
  }
}

run "jumpbox_does_not_accept_ssh_from_the_internet" {
  command = plan

  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.jumpbox[0].security_rule :
      r.source_address_prefix != "*" && r.source_address_prefix != "Internet"
      if r.direction == "Inbound" && r.access == "Allow"
    ])
    error_message = "no inbound allow rule on the jump box may accept traffic from the internet"
  }
}

run "passwords_are_disabled" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.jumpbox[0].disable_password_authentication
    error_message = "password authentication must stay off; Entra ID is the login path"
  }
}

run "entra_id_login_is_installed" {
  command = plan

  # Dormant on the Developer SKU, which cannot do Entra ID auth — kept so that
  # upgrading Bastion to Basic retires the Key Vault key immediately.
  assert {
    condition     = azurerm_virtual_machine_extension.jumpbox_entra_login[0].type == "AADSSHLoginForLinux"
    error_message = "the Entra ID SSH login extension must stay installed, so a Bastion SKU upgrade is all that is needed to drop the shared key"
  }

  assert {
    condition     = one(azurerm_linux_virtual_machine.jumpbox[0].identity[*].type) == "SystemAssigned"
    error_message = "the Entra ID login extension requires a managed identity on the VM"
  }
}

run "sign_in_key_is_reachable_and_rsa" {
  command = plan

  # The Developer SKU cannot authenticate with Entra ID, so this key is the only
  # way in. If it is not in the vault, the jump box is unreachable.
  assert {
    condition     = azurerm_key_vault_secret.jumpbox_ssh_private_key[0].name == "jumpbox-ssh-private-key"
    error_message = "the sign-in key must be stored in Key Vault; Bastion Developer has no other usable authentication method here"
  }

  # The portal documents the private key as needing "-----BEGIN RSA PRIVATE
  # KEY-----" form, which ED25519 cannot produce.
  assert {
    condition     = tls_private_key.jumpbox_admin[0].algorithm == "RSA"
    error_message = "the sign-in key must be RSA — Bastion's Key Vault flow expects an RSA-format PEM"
  }
}

run "key_vault_is_rbac_governed" {
  command = plan

  # The vault is publicly reachable by necessity, so RBAC is the only thing
  # standing in front of the key.
  assert {
    condition     = azurerm_key_vault.jumpbox[0].rbac_authorization_enabled
    error_message = "the vault must use RBAC, not access policies — it is the sole guard on a publicly reachable secret"
  }

  assert {
    condition     = azurerm_role_assignment.jumpbox_secrets[0].role_definition_name == "Key Vault Secrets Officer"
    error_message = "Terraform needs data-plane rights to write the key; Owner does not grant them in RBAC mode"
  }
}

run "bastion_uses_the_free_developer_sku" {
  command = plan

  assert {
    condition     = azurerm_bastion_host.this[0].sku == "Developer"
    error_message = "Bastion must stay on the Developer SKU; Basic and above are billed hourly from deployment"
  }
}

run "jumpbox_can_be_turned_off_entirely" {
  command = plan

  variables {
    jumpbox_enabled = false
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.jumpbox) == 0
    error_message = "jumpbox_enabled = false must create no VM"
  }

  # Bastion fronts only the jump box, so it must not outlive it and keep billing
  # or dangle against nothing.
  assert {
    condition     = length(azurerm_bastion_host.this) == 0
    error_message = "Bastion must not be created when there is no jump box to reach"
  }

  assert {
    condition     = length(azurerm_subnet.jumpbox) == 0
    error_message = "jumpbox_enabled = false must leave no orphaned subnet"
  }

  # The vault exists only to hold the sign-in key for a VM that is now gone.
  assert {
    condition     = length(azurerm_key_vault.jumpbox) == 0
    error_message = "jumpbox_enabled = false must leave no vault holding a key to a VM that does not exist"
  }
}

run "bastion_can_be_disabled_where_the_region_lacks_it" {
  command = plan

  variables {
    bastion_enabled = false
  }

  assert {
    condition     = length(azurerm_bastion_host.this) == 0
    error_message = "bastion_enabled = false must create no Bastion host"
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.jumpbox) == 1
    error_message = "disabling Bastion must leave the jump box in place — the portal can deploy Bastion Developer on demand"
  }
}
