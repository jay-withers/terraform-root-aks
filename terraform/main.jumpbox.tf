# The way in. The API server has no public endpoint, so administration happens
# from a VM inside the VNet, reached through Azure Bastion — no public IP on the
# VM, no inbound port open to the internet, no VPN client, and no DNS
# infrastructure: the VM uses Azure DNS at 168.63.129.16 by default, which
# resolves both the AKS-managed private zone and the private endpoint zones in
# main.keyvault.tf natively.
#
# Windows, so that a browser inside the VNet can reach the data planes that have
# no public endpoint — chiefly the workload Key Vault, whose portal Secrets blade
# fails from anywhere else (see local.workload_key_vault_network). The portal
# itself is public and the AKS blade proxies through ARM, so neither needs this
# box; the private-endpoint resources do.
#
# Deallocate it when it is not in use. Compute stops billing; the disk does not,
# and a Windows image carries a 127 GiB OS disk against Ubuntu's 30 GiB. The
# Windows Server licence is charged per vCPU while the VM is running, so an
# instance left on is the single largest line item this repo can produce.
#
# The subnet is a property of the VNet, in local.subnets; the object inputs the VM
# and vault modules take are in locals.tf, where tests can assert on them.

module "nsg_jumpbox" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5"
  count   = var.jumpbox_enabled ? 1 : 0

  name                = "${module.naming.network_security_group.name}-jumpbox"
  location            = local.location
  resource_group_name = local.resource_group_name
  security_rules      = local.jumpbox_nsg_rules
  tags                = local.tags
}

# The credential operators actually sign in with.
#
# A password, which the Linux box deliberately avoided. Windows has no equivalent
# of an SSH public key, and Bastion's Key Vault sign-in flow is Linux-only — it
# offers "SSH Private Key from Azure Key Vault" and nothing comparable for RDP.
# Entra ID login would sidestep it, but portal Entra ID authentication needs
# Bastion Basic or above, and Basic is billed hourly from deployment.
#
# So the password is generated here rather than chosen, stored in Key Vault
# rather than shared, and never printed: the outputs expose the secret's name,
# not its value. Rotation is a replace, same as the key it succeeds:
#   terraform apply -replace='random_password.jumpbox_admin[0]'
#
# keepers is deliberately empty — a password that regenerated on unrelated input
# changes would silently diverge from the one already set on the VM.
resource "random_password" "jumpbox_admin" {
  count = var.jumpbox_enabled ? 1 : 0

  length = 32

  # Windows enforces three of four character classes; asking for all four rather
  # than trusting a random draw to satisfy it.
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2

  # The default set includes characters the RDP client and the portal's copy path
  # handle badly. These are the ones that survive both intact.
  override_special = "!#$%*+-=?_"
}

# RBAC rather than access policies, matching how the cluster is authorized.
#
# The vault keeps its public endpoint — the only resource here that does. Under
# the Linux box that was load-bearing, because Bastion itself read the key from
# the vault at connect time, from address ranges Microsoft does not publish. A
# password is read by an operator instead, so the endpoint can now be narrowed to
# known addresses with var.jumpbox_key_vault_allowed_ip_ranges. Off by default:
# the deploying identity writes this secret over the same data plane, and a
# GitHub-hosted runner has no stable address to put on the list.
#
# RBAC is the guard either way; the allow list is a second one, not a substitute.
# Application secrets go in the workload vault instead.
module "jumpbox_key_vault" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.11"
  count   = var.jumpbox_enabled ? 1 : 0

  name                = local.jumpbox_key_vault_name
  location            = local.location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # The public endpoint stays on whatever the ACL says: with no private endpoint on
  # this vault, disabling it would deny everyone, including the operator fetching
  # the password. See local.jumpbox_key_vault_network_acls — null until
  # var.jumpbox_key_vault_allowed_ip_ranges is set, because the module's own
  # default is a default-deny firewall that would shut out Terraform too.
  network_acls                  = local.jumpbox_key_vault_network_acls
  public_network_access_enabled = true

  role_assignments = local.jumpbox_key_vault_role_assignments

  # Split because the value is sensitive and cannot be used in a for_each. Keys match.
  secrets       = local.jumpbox_key_vault_secrets
  secrets_value = { admin_password = random_password.jumpbox_admin[0].result }
}

module "jumpbox" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "~> 0.21"
  count   = var.jumpbox_enabled ? 1 : 0

  name                = "${module.naming.windows_virtual_machine.name}-jumpbox"
  location            = local.location
  resource_group_name = local.resource_group_name
  os_type             = "Windows"
  sku_size            = var.jumpbox_vm_size
  tags                = local.tags

  # The Azure resource name may run long; the Windows computer name may not — 15
  # characters, and the API rejects the whole create rather than truncating. The
  # naming module already caps its output at 15, so this is the one safe source.
  computer_name = local.jumpbox_computer_name

  # Regional, not zonal — a box that is deallocated most of the time gains nothing
  # from a zone pin, and it would tie the VM size to that zone's availability.
  zone = null

  account_credentials = local.jumpbox_account_credentials
  managed_identities  = local.jumpbox_managed_identities
  network_interfaces  = local.jumpbox_network_interfaces
  extensions          = local.jumpbox_extensions

  # Left at the image's own size, which for Windows Server is 127 GiB — it cannot
  # be shrunk below the image, only grown. That disk bills whether the VM is
  # running or deallocated, and is now the standing cost of this box.
  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  # Gen2 image, because the v6 VM families are Gen2-only — a "-g2"-less SKU here
  # fails the create with a generation mismatch, not a helpful message.
  #
  # Datacenter rather than Azure Edition: Azure Edition's draw is hotpatching, and
  # hotpatching on Server 2025 became a paid per-core subscription in 2025. This
  # box reboots for patches instead, which is free and, on something deallocated
  # most of the time, no inconvenience.
  source_image_reference = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  # No custom_data: Windows writes it to C:\AzureData\CustomData.bin and never
  # runs it. The tooling install is a Custom Script extension instead — see
  # local.jumpbox_extensions.

  # A long-lived admin box is exactly the thing that rots. Let the platform patch
  # it rather than relying on someone remembering to.
  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = false

  # AADLoginForWindows and the bootstrap script both depend on this.
  allow_extension_operations = true

  # Off, against the module's default of on: it needs the EncryptionAtHost feature
  # registered on the subscription or apply fails outright, and it protects a temp
  # disk that stores nothing. Turn it on once registered; needs the VM deallocated.
  encryption_at_host_enabled = false
}

# The Developer SKU is free and needs no AzureBastionSubnet. If the landing zone's
# region does not support it, set bastion_enabled = false. The portal will still offer to
# deploy Bastion Developer on demand when you connect, and an unmanaged resource
# appearing under a VNet Terraform owns is worse than choosing not to declare it.
module "bastion" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "~> 0.9"
  count   = var.jumpbox_enabled && var.bastion_enabled ? 1 : 0

  name      = local.bastion_name
  location  = local.location
  parent_id = local.resource_group_id
  sku       = local.bastion_sku
  tags      = local.tags

  # Developer attaches to a VNet rather than a subnet, so it takes the VNet ID and
  # rejects availability zones.
  virtual_network_id = module.vnet.resource_id
  zones              = []

  # Bastion needs the VNet in a Succeeded state, and every subnet write puts it back
  # into Updating. Referencing the VNet ID alone does not wait for that, and a first
  # apply then fails with BastionHostVirtualNetworkNotFound — which reads like a
  # region-support problem and is not one.
  depends_on = [module.vnet]
}
