# Loki's log store: a blob account answering only on a private endpoint, written to
# with workload identity rather than an account key.
#
# This is the metrics stack's counterpart. Prometheus keeps its series on a managed
# disk sized for one node and pinned to one zone, and that is deliberate — metrics
# there are disposable. Logs are the thing someone goes looking for after the node
# that produced them is gone, so they go somewhere that outlives any node: object
# storage, at a few pence per gigabyte per month, which is also the cheapest durable
# thing Azure sells.
#
# Costs roughly a private endpoint a month. The zone is already the hub's, and the
# blob itself rounds to nothing at this volume.

# Without a link the endpoint has an address nothing on this VNet can resolve:
# clients keep resolving the public name to a public IP the account no longer
# answers on, and Loki reports a connection timeout rather than a DNS failure.
#
# Same division as the vault's link in main.keyvault.tf. The zone lives in the hub
# and is not created here — the connectivity component already hosts
# privatelink.blob.core.windows.net alongside privatelink.vaultcore.azure.net — so
# this creates only its own link, which is a child of the zone and therefore written
# in the hub's resource group.
#
# That write needs the landingzones component to name this zone in this landing
# zone's linkable_dns_zones. It currently grants only the vault zone, so the first
# apply of this file fails with AuthorizationFailed until that one-line grant lands.
# The fix is there and never a broader role here.
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "vnetlink-blob-${local.name_suffix}"
  resource_group_name   = module.hub_naming.resource_group.name
  private_dns_zone_name = data.azurerm_private_dns_zone.blob.name
  virtual_network_id    = module.vnet.resource_id
  tags                  = local.tags

  # Records come from the endpoint's DNS zone group; nothing self-registers here.
  registration_enabled = false
}

# shared_access_key_enabled = false is the point of the whole arrangement, not a
# hardening afterthought: with the keys disabled there is no credential for this
# account in existence, so there is none to leak into a Kubernetes Secret, a values
# file or a support ticket. Every caller — Loki, the operator at the jump box — has
# to present an Entra ID token and be caught by an RBAC grant. It also means a
# connection string is not a fallback when something does not work.
module "loki_storage" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.6"

  name      = local.loki_storage_account_name
  location  = local.location
  parent_id = local.resource_group_id
  tags      = local.tags

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = local.loki_storage_replication_type

  shared_access_key_enabled = false
  min_tls_version           = "TLS1_2"

  # In locals.tf so tests can assert on them — a module's inputs are not reachable
  # from a `run` block, but the values that fed them are. Same reason as the vault's.
  public_network_access_enabled = local.loki_storage_network.public_network_access_enabled
  network_rules                 = local.loki_storage_network.network_rules
  private_endpoints             = local.loki_private_endpoints

  # Worth knowing why this works at all, because the equivalent on the workload
  # vault does not: Terraform cannot write a secret into the vault, because a
  # secret is a data-plane object and the data plane answers only on the private
  # endpoint that CI is not behind. Containers look like the same problem and are
  # not. This module is azapi-based throughout, so it creates them through ARM —
  # Microsoft.Storage/storageAccounts/blobServices/containers is a control-plane
  # resource type — which a GitHub-hosted runner can reach and which the vended
  # identity's Contributor already covers. No firewall exception, no operator step.
  #
  # The distinction is the module version, not the resource: azurerm_storage_container
  # reaches for the data plane and would fail here with a 403 that reads like an
  # RBAC problem and is not.
  containers = local.loki_containers
}

# Platform infrastructure that happens to run as a pod, exactly like external-dns —
# and deliberately not an entry in var.workload_identities, which is for tenant
# workloads and carries an opt-in to the workload Key Vault this has no use for.
module "loki_identity" {
  #checkov:skip=CKV_TF_1:Registry-sourced AVM module pinned to a version constraint; commit-hash pinning does not apply to Terraform Registry sources.
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "~> 0.5"

  name                = "${module.naming.user_assigned_identity.name}-loki"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.tags

  federated_identity_credentials = {
    kubernetes = {
      name     = "fic-loki"
      audience = ["api://AzureADTokenExchange"]
      issuer   = module.aks.oidc_issuer_profile_issuer_url

      # Matched by Entra ID as a literal string and never normalised. Held in
      # local.loki_service_account so the manifests and this cannot drift; a
      # mismatch is neither a plan nor an apply failure, it is an AADSTS70021 the
      # first time Loki asks for a token.
      subject = "system:serviceaccount:${local.loki_service_account.namespace}:${local.loki_service_account.name}"
    }
  }
}

# Scoped to the account, not to the resource group. Loki writes chunks continuously
# and compacts by deleting them, so it genuinely needs data-plane write and delete —
# there is no narrower built-in role that works. Confining it to this one account is
# therefore the whole of the containment: at group scope the same grant would reach
# every storage account that ever lands in this landing zone.
#
# "Storage Blob Data Contributor", not "Contributor": the data roles carry no
# control-plane rights at all, so this cannot read the account keys back — which
# would otherwise be a way around shared_access_key_enabled = false.
resource "azurerm_role_assignment" "loki_storage" {
  scope                = module.loki_storage.resource_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.loki_identity.principal_id
}

# The operator's grant, for reading logs out of the account directly when Grafana
# itself is the thing that is broken. Without it the account is reachable from the
# jump box but answers 403 to the person sitting on it — the keys are disabled, so
# there is no other way in, and the first time anyone discovers that is mid-incident.
resource "azurerm_role_assignment" "loki_storage_deployer" {
  scope                = module.loki_storage.resource_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}
