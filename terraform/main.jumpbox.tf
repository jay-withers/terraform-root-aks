# The way in. The API server has no public endpoint, so administration happens
# from a VM inside the VNet, reached through Azure Bastion — no public IP on the
# VM, no inbound port open to the internet, no VPN client, and no DNS
# infrastructure: the VM uses Azure DNS at 168.63.129.16 by default, which
# resolves the AKS-managed private zone natively.
#
# Deallocate it when it is not in use. Compute stops billing; the disk does not.

resource "azurerm_subnet" "jumpbox" {
  #checkov:skip=CKV2_AZURE_31:An NSG is associated below. Checkov cannot follow the reference through the count index, and reports the same subnet clean once count is removed.
  count = var.jumpbox_enabled ? 1 : 0

  name                 = "snet-jumpbox"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.jumpbox_subnet_address_prefix]
}

resource "azurerm_network_security_group" "jumpbox" {
  count = var.jumpbox_enabled ? 1 : 0

  name                = "nsg-jumpbox"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  # Bastion Developer deploys into this VNet on connect rather than into a
  # dedicated AzureBastionSubnet, so its traffic arrives with a VirtualNetwork
  # source. Azure's default rules would already permit this; the rule is spelled
  # out so that the reason port 22 must stay reachable is visible to whoever
  # tightens these next. Note the source is the VNet, never the internet.
  security_rule {
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

resource "azurerm_subnet_network_security_group_association" "jumpbox" {
  count = var.jumpbox_enabled ? 1 : 0

  subnet_id                 = azurerm_subnet.jumpbox[0].id
  network_security_group_id = azurerm_network_security_group.jumpbox[0].id
}

resource "azurerm_network_interface" "jumpbox" {
  count = var.jumpbox_enabled ? 1 : 0

  name                = "nic-jumpbox"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  # No public_ip_address_id: Bastion is the only way to reach this.
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpbox[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

# The key operators actually sign in with.
#
# Bastion's Developer SKU cannot do Microsoft Entra ID authentication — that is
# Basic SKU and above — so a key is the way in, and it has to be retrievable.
# Key Vault is where it lives: Bastion reads the private key straight out of the
# vault at connect time, so it is never downloaded, emailed, or left sitting in
# someone's ~/.ssh directory.
#
# RSA rather than ED25519 deliberately: the portal documents the private key as
# needing to be in "-----BEGIN RSA PRIVATE KEY-----" form. That is what
# private_key_pem emits for RSA, and what an ED25519 key cannot produce.
resource "tls_private_key" "jumpbox_admin" {
  count = var.jumpbox_enabled ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# RBAC rather than access policies, matching how the cluster is authorized.
#
# The vault keeps its public endpoint. Bastion fetches the secret from Microsoft's
# own infrastructure, not from inside this VNet, so a network ACL restricting it
# to the VNet would break the one thing this vault exists for. RBAC is the guard.
resource "azurerm_key_vault" "jumpbox" {
  #checkov:skip=CKV_AZURE_109:A network ACL would block Bastion from reading the key at connect time, which is this vault's only purpose. Access is governed by RBAC, and the sole secret opens a VM that has no public IP.
  #checkov:skip=CKV2_AZURE_32:Same reasoning — a private endpoint would put the secret out of Bastion's reach.
  #checkov:skip=CKV_AZURE_189:Same reasoning — Bastion reads this secret from Microsoft's infrastructure, not from inside the VNet, so disabling public network access would lock everyone out of the jump box.
  count = var.jumpbox_enabled ? 1 : 0

  # name_unique, not name: a vault's name is a global DNS label
  # (<name>.vault.azure.net), not a per-subscription one, so a readable name like
  # "kv-main-dev" collides with whichever tenant in the world claimed it first —
  # and the failure surfaces at apply as VaultAlreadyExists. The random suffix
  # comes from the naming module and is held in state, so it is stable across
  # applies. Read the real name from the jumpbox_key_vault_name output.
  name                = module.naming.key_vault.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}

# Terraform needs data-plane rights to write the secret below, and operators need
# them to read it at connect time. Owner grants neither: in RBAC mode the
# management plane and the data plane are separate grants.
#
# This covers whoever runs Terraform. Anyone else who needs to sign in to the jump
# box needs "Key Vault Secrets User" on this vault, on top of the Reader roles
# Bastion itself requires.
resource "azurerm_role_assignment" "jumpbox_secrets" {
  count = var.jumpbox_enabled ? 1 : 0

  scope                = azurerm_key_vault.jumpbox[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Select this secret in the Bastion connection pane, with authentication type
# "SSH Private Key from Azure Key Vault" and username "azureuser".
#
# Written by Terraform rather than pasted through the portal on purpose: the
# portal's secret editor mangles PEM line endings and yields a key that fails to
# authenticate with no useful error.
resource "azurerm_key_vault_secret" "jumpbox_ssh_private_key" {
  #checkov:skip=CKV_AZURE_41:Expiry is available via var.jumpbox_key_expiry_date but off by default. Key Vault refuses to serve an expired secret, so a date set and forgotten locks everyone out of the only route into a private cluster. Opt in once a rotation process exists to meet it.
  count = var.jumpbox_enabled ? 1 : 0

  name         = "jumpbox-ssh-private-key"
  value        = tls_private_key.jumpbox_admin[0].private_key_pem
  key_vault_id = azurerm_key_vault.jumpbox[0].id
  content_type = "application/x-pem-file"
  tags         = local.tags

  # Note that rotation is not a re-apply: tls_private_key is persisted in state
  # and regenerates only when replaced, e.g.
  #   terraform apply -replace='tls_private_key.jumpbox_admin[0]'
  # which rewrites this secret and rebuilds the VM with the new public key.
  expiration_date = var.jumpbox_key_expiry_date

  # The data-plane grant has to land before the write is attempted. Role
  # assignments take a moment to propagate, so a first apply can still need one
  # retry even with this ordering in place.
  depends_on = [azurerm_role_assignment.jumpbox_secrets]
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  #checkov:skip=CKV_AZURE_50:Extensions are required, not incidental — AADSSHLoginForLinux is installed so that upgrading Bastion to Basic retires the Key Vault key in favour of Entra ID sign-in. Disabling extension operations would foreclose that.
  count = var.jumpbox_enabled ? 1 : 0

  name                = "vm-jumpbox"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.jumpbox_vm_size
  network_interface_ids = [
    azurerm_network_interface.jumpbox[0].id,
  ]
  tags = local.tags

  # The account operators sign in as, with the matching private key held in Key
  # Vault. Passwords stay off — a password on a shared admin box is a credential
  # that gets written down and never rotated.
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.jumpbox_admin[0].public_key_openssh
  }

  # The extension below binds SSH to Entra ID, which needs an identity on the VM.
  identity {
    type = "SystemAssigned"
  }

  # A long-lived admin box is exactly the thing that rots. Let the platform patch
  # it rather than relying on someone remembering to.
  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(local.jumpbox_cloud_init)

  # The image is patched in place and the tooling reinstalls from cloud-init, so
  # a new image version is not a reason to rebuild the box out from under an
  # operator mid-session.
  lifecycle {
    ignore_changes = [source_image_reference[0].version]
  }
}

# Installed, but dormant on the Developer SKU: Entra ID authentication through
# the portal needs Bastion Basic or above. It is kept because it costs nothing
# and turns "upgrade Bastion to Basic" into a one-line change that immediately
# retires the Key Vault key above — at which point sign-in becomes an identity
# with MFA and conditional access behind it, rather than a shared secret.
#
# It also enables `az ssh vm` for anyone who reaches the VNet another way.
#
# Note that operators still need "Virtual Machine Administrator Login" (or
# "Virtual Machine User Login") on the VM, and — separately — an AKS role such as
# "Azure Kubernetes Service RBAC Reader" on the cluster. Reaching the box is not
# the same as being allowed to do anything once kubectl authenticates.
resource "azurerm_virtual_machine_extension" "jumpbox_entra_login" {
  count = var.jumpbox_enabled ? 1 : 0

  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.jumpbox[0].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = local.tags
}

# The Developer SKU is free and needs no AzureBastionSubnet — it runs on shared
# infrastructure that attaches to the VNet on connect. The trade-offs: browser
# sessions only (native client and file transfer are Standard SKU), one VM at a
# time, and it is not offered in every region.
#
# If var.location does not support it, set bastion_enabled = false. The portal
# will still offer to deploy Bastion Developer on demand when you connect, and
# an unmanaged resource appearing under a VNet Terraform owns is worse than
# choosing not to declare it.
resource "azurerm_bastion_host" "this" {
  count = var.jumpbox_enabled && var.bastion_enabled ? 1 : 0

  name                = "bas-${var.workload_name}-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Developer"
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = local.tags

  # Bastion attaches to the VNet and requires it in a Succeeded provisioning
  # state. Referencing the VNet alone is not enough to guarantee that: every
  # subnet write puts the VNet back into Updating, and Terraform is free to
  # create Bastion in parallel with those. Without this, a first apply fails with
  # BastionHostVirtualNetworkNotFound — which reads like a region-support problem
  # and is not one.
  depends_on = [
    azurerm_subnet.nodes,
    azurerm_subnet.api_server,
    azurerm_subnet.jumpbox,
    azurerm_subnet_network_security_group_association.nodes,
    azurerm_subnet_network_security_group_association.api_server,
    azurerm_subnet_network_security_group_association.jumpbox,
  ]
}
