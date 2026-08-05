# The way in. The API server has no public endpoint, so administration happens
# from a VM inside the VNet, reached through Azure Bastion — no public IP on the
# VM, no inbound port open to the internet, no VPN client, and no DNS
# infrastructure: the VM uses Azure DNS at 168.63.129.16 by default, which
# resolves both the AKS-managed private zone and the private endpoint zones in
# main.keyvault.tf natively.
#
# Deallocate it when it is not in use. Compute stops billing; the disk does not.
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
# The vault keeps its public endpoint — the only resource here that does. Bastion
# fetches the secret from Microsoft's own infrastructure, not from inside this VNet,
# so a network ACL or private endpoint would break the one thing this vault exists
# for. RBAC is the guard. Application secrets go in the workload vault instead.
module "jumpbox_key_vault" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.10"
  count   = var.jumpbox_enabled ? 1 : 0

  name                = local.jumpbox_key_vault_name
  location            = local.location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # Load-bearing: the module defaults to a default-deny firewall, which would leave
  # Bastion unable to read the key at connect time.
  network_acls                  = null
  public_network_access_enabled = true

  role_assignments = local.jumpbox_key_vault_role_assignments

  # Split because the value is sensitive and cannot be used in a for_each. Keys match.
  secrets       = local.jumpbox_key_vault_secrets
  secrets_value = { ssh_private_key = tls_private_key.jumpbox_admin[0].private_key_pem }
}

module "jumpbox" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "~> 0.21"
  count   = var.jumpbox_enabled ? 1 : 0

  name                = "${module.naming.linux_virtual_machine.name}-jumpbox"
  location            = local.location
  resource_group_name = local.resource_group_name
  os_type             = "Linux"
  sku_size            = var.jumpbox_vm_size
  tags                = local.tags

  # Regional, not zonal — a box that is deallocated most of the time gains nothing
  # from a zone pin, and it would tie the VM size to that zone's availability.
  zone = null

  account_credentials = local.jumpbox_account_credentials
  managed_identities  = local.jumpbox_managed_identities
  network_interfaces  = local.jumpbox_network_interfaces
  extensions          = local.jumpbox_extensions

  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(local.jumpbox_cloud_init)

  # A long-lived admin box is exactly the thing that rots. Let the platform patch
  # it rather than relying on someone remembering to.
  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = false

  # AADSSHLoginForLinux depends on this, so it is not incidental.
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
