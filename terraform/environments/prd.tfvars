# Production environment — full zone resilience: one node per availability zone
# in every pool, Standard tier for the API server uptime SLA.
#
# NOTE: the minimum footprint is 18 vCPU (9 nodes x 2), and upgrade surge needs
# headroom on top — so this requires the westeurope regional + Standard Dsv6
# quota raised to ~24+ (default is 20). Apply will fail with
# ErrCode_InsufficientVCPUQuota until that increase is approved.
#
#   min vCPU = 3(system) + 3(apps) + 3(monitoring) nodes x 2 = 18

environment = "prd"

# A month, against fourteen days elsewhere. This is the copy anyone goes back to
# after an incident review, and at production's log volume it is still a few pounds
# a month of blob — the cost that matters here is the monitoring pool, not the
# storage. Raise deliberately: retention is enforced by Loki's compactor, so
# lengthening it grows the account from the day it changes rather than retroactively.
loki_retention_days = 30

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
