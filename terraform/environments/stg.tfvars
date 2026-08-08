# Staging environment — a scaled-down mirror of production.
# Multi-zone and Standard tier so it exercises the same resilience paths as prd,
# but with lower node counts.

environment = "stg"

system_node_count = 2

apps_min_count = 2
apps_max_count = 4

monitoring_min_count = 2
monitoring_max_count = 3

# --- GitOps ------------------------------------------------------------------
# Same repository as every other environment; the path derives from `environment`
# in locals.tf. The repository is public, so no credentials are needed.
flux_git_repository_url = "https://github.com/jay-withers/terraform-root-aks.git"

# The example tenant. namespace and service_account must match
# gitops/tenants/onboarding/ exactly — Entra ID matches the federated credential
# subject by literal string and never normalises it.
workload_identities = {
  whoami = {
    namespace       = "tenant-whoami"
    service_account = "whoami"
  }
}
