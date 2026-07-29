# Development environment — optimised for cost, not resilience.
# Single zone, minimal nodes, no uptime SLA.

environment = "dev"
location    = "westeurope"

# Single zone keeps dev cheap; no cross-zone HA.
availability_zones = ["1"]

# Free tier — no financially-backed API server SLA needed in dev.
sku_tier = "Free"

# Minimal, fixed-size pools.
system_node_count = 1

apps_min_count = 1
apps_max_count = 2

monitoring_min_count = 1
monitoring_max_count = 1

tags = {
  managed-by = "terraform"
}
