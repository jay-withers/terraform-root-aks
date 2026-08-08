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
  #
  # Enforced multi-tenancy is load-bearing for the tree in gitops/: it is why every
  # tenant carries its own GitRepository in its own namespace and a Kustomization
  # that names a serviceAccountName to reconcile as. When a tenant Kustomization
  # reports a blocked cross-namespace reference, or a permissions error naming
  # system:serviceaccount:<namespace>:default, the fix is that tenant's RoleBinding
  # and serviceAccountName — not { "multiTenancy.enforce" = "false" } here, which is
  # the first thing a search result will suggest and gives every tenant the run of
  # the cluster.
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

  # Exactly one Kustomization is declared here, and it builds only the bootstrap
  # tree — the Flux Kustomization and GitRepository objects that own everything
  # else. Two reasons it cannot be more than that:
  #
  #   * this block has no service_account_name attribute, so a Kustomization
  #     declared in Terraform can never carry the impersonation that enforced
  #     multi-tenancy requires of a tenant;
  #   * the comment above already says the repository, not this module, is the
  #     source of truth once this exists.
  kustomizations {
    name                     = "cluster"
    path                     = local.flux_kustomization_path
    sync_interval_in_seconds = var.flux_sync_interval_seconds

    # Prune: an object whose manifest leaves the repository is deleted from the
    # cluster. Without this, deletions in git are silently ignored and the cluster
    # accumulates whatever was ever applied to it.
    garbage_collection_enabled = true

    # False, against the ARM default of true. A Flux Kustomization is not Ready
    # until the tree it builds is, so waiting here waits for cert-manager, Envoy
    # Gateway and the whole monitoring stack to come up inside the ARM call's
    # ten-minute timeout, on a cluster whose nodes are still pulling images. The
    # health gating that matters lives in the git-declared Kustomizations' dependsOn
    # and wait, where the dependency graph actually is.
    wait = false

    # Emitted only when there is something to substitute — ARM accepts an empty
    # postBuild and then shows it as a permanent diff.
    dynamic "post_build" {
      for_each = length(local.flux_post_build_substitutions) > 0 ? [1] : []

      content {
        substitute = local.flux_post_build_substitutions
      }
    }
  }

  # The configuration is rejected until the extension has finished installing, and
  # the cluster_id above creates no dependency between the two.
  #
  # The other two are ordering rather than syntax. Flux starts reconciling the
  # moment this resource is created, and the tenant's SecretProviderClass mounts
  # against an identity that must already hold "Key Vault Secrets User" — without
  # these the graph is free to create the configuration first and the pod spends its
  # first minutes in ContainerCreating behind a 403 from the CSI driver. The
  # substitutions already create the module.workload_identity edge implicitly; it is
  # written out so that removing a substitution later does not quietly reintroduce
  # the race. module.workload_key_vault is the one that exists only here, because
  # the role assignments live inside that module.
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux,
    module.workload_identity,
    module.workload_key_vault,
  ]
}
