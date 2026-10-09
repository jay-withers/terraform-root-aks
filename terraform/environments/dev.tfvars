# Development environment — the cost floor, not a resilience test bed.
# One zone, one node, no uptime SLA, and stopped outside 12:00–22:00 UK time by
# .github/workflows/cd-dev-power.yml.

# Single zone keeps dev cheap; no cross-zone HA.
availability_zones = ["1"]

# Free tier — no financially-backed API server SLA needed in dev.
sku_tier = "Free"

# One node runs everything: system add-ons, Flux, the observability stack and the
# tenants. The apps and monitoring pools are not created, so their variables are
# left unset here.
single_node_pool  = true
system_node_count = 1

# Memory, not CPU, is the constraint — every request in gitops/ adds up to under
# half a vCPU but the monitoring stack alone outgrew one 8 GiB D2s_v6. 2 vCPU and
# 16 GiB for less than the 4 vCPU D4as_v6 would cost.
system_vm_size = "Standard_E2as_v6"

# A P6 rather than the default 128 GiB P10: half the price, and AKS chooses the
# Premium SKU itself, so the size is the only lever.
os_disk_size_gb = 64

# Node image upgrades surge one extra node, drain onto it and remove the old one,
# so the cluster is briefly two nodes and then one again. That only happens if the
# cluster is running, and it is stopped at the module's default 19:00 UTC — so the
# window sits inside the 12:00–22:00 UK running hours instead. 13:00–17:00 UTC is
# inside them in both GMT and BST.
node_os_maintenance_window = {
  start_time = "13:00"
}

# The cluster stops at 22:00; the jump box follows it rather than billing a Windows
# licence overnight. Nothing starts it — do that by hand when it is needed.
jumpbox_auto_shutdown_time = "2200"

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
