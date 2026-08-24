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

# Loki now shares this pool with the metrics stack, which is what makes the second
# node above load-bearing rather than headroom — expect the autoscaler to take it.
# Seven days rather than the fourteen-day default: dev logs are for debugging what
# happened this week, and the blob account is billed on what is stored.
loki_retention_days = 7

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
