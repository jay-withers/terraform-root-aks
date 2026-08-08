# Development environment — optimised for cost, not resilience.
# Single zone, minimal nodes, no uptime SLA.

# Single zone keeps dev cheap; no cross-zone HA.
availability_zones = ["1"]

# Free tier — no financially-backed API server SLA needed in dev.
sku_tier = "Free"

# Minimal, fixed-size pools.
system_node_count = 1

apps_min_count = 1
apps_max_count = 2

monitoring_min_count = 1

# Two, not one. A single Standard_D2s_v6 (2 vCPU, 8 GiB) is a hard ceiling for
# Prometheus, Alertmanager, Grafana, kube-state-metrics and the operator together,
# and with max equal to min the autoscaler cannot help — pods simply stay Pending.
monitoring_max_count = 2

# --- GitOps ------------------------------------------------------------------
# This cluster reconciles from this same repository. The per-environment path is
# derived in locals.tf as "gitops/clusters/<environment>"; do not repeat it here.
# The repository is public, so no credentials are needed.
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
