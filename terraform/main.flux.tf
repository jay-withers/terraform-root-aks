# GitOps with Flux v2, installed as the AKS `microsoft.flux` cluster extension
# rather than by running `flux bootstrap` against the API server. Azure owns the
# controllers' lifecycle and upgrades, and the install happens through ARM — which
# matters here because the API server is private and Terraform has no route to it.
#
# Two prerequisites live outside this module:
#
#   * The Microsoft.KubernetesConfiguration and Microsoft.ContainerService
#     resource providers must be registered on the subscription. Extension
#     creation fails with MissingSubscriptionRegistration otherwise.
#   * The git host must be reachable from the node subnet. Egress is the
#     loadBalancer path (see locals.tf), so a public host works as-is; a private
#     one needs both a route and DNS.
#
# The controllers carry no tolerations, so they land on the apps pool — the system
# pool is tainted CriticalAddonsOnly=true:NoSchedule.
resource "azurerm_kubernetes_cluster_extension" "flux" {
  count = var.flux_enabled ? 1 : 0

  name           = "flux"
  cluster_id     = module.aks.resource_id
  extension_type = "microsoft.flux"

  # configuration_settings is deliberately left at the extension defaults:
  # multi-tenancy is enforced (a Kustomization may not reference a source in
  # another namespace) and the image automation and reflector controllers are off.
  # Both are configuration_settings here if that ever needs to change.
}

# Points the controllers at a repository. The extension above installs Flux; this
# is what creates the GitRepository and Kustomization objects that make it sync.
#
# Only the initial state is Terraform's: the Kustomization prunes objects removed
# from git, so once this exists the repository — not this module — is the source of
# truth for what runs in the cluster.
resource "azurerm_kubernetes_flux_configuration" "this" {
  count = local.flux_configuration_enabled ? 1 : 0

  name       = "flux-system"
  cluster_id = module.aks.resource_id

  # Cluster scope puts the reconciler's service account at cluster level, which is
  # what a repository that installs namespaces and CRDs needs. Namespace scope
  # would confine it to one namespace.
  namespace = "flux-system"
  scope     = "cluster"

  git_repository {
    url                      = var.flux_git_repository_url
    reference_type           = "branch"
    reference_value          = var.flux_git_branch
    sync_interval_in_seconds = var.flux_sync_interval_seconds

    # All four are null for a public repository. The ARM API takes them
    # base64-encoded; var.flux_git_credentials takes them in their natural form so
    # nobody has to pre-encode a PEM. See locals.tf.
    https_user             = var.flux_git_credentials.https_user
    https_key_base64       = local.flux_git_auth.https_key_base64
    ssh_private_key_base64 = local.flux_git_auth.ssh_private_key_base64
    ssh_known_hosts_base64 = local.flux_git_auth.ssh_known_hosts_base64
  }

  kustomizations {
    name                     = "cluster"
    path                     = var.flux_git_path
    sync_interval_in_seconds = var.flux_sync_interval_seconds

    # Prune: an object whose manifest leaves the repository is deleted from the
    # cluster. Without this, deletions in git are silently ignored and the cluster
    # accumulates whatever was ever applied to it.
    garbage_collection_enabled = true
  }

  # The configuration is rejected until the extension has finished installing, and
  # the cluster_id above creates no dependency between the two.
  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}
