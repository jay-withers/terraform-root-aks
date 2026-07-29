# Staging environment — a scaled-down mirror of production.
# Multi-zone and Standard tier so it exercises the same resilience paths as prd,
# but with lower node counts.

environment = "stg"
location    = "westeurope"

# Zone-resilient, matching production topology.
availability_zones = ["1", "2", "3"]

# Standard tier so staging validates the same SLA/behaviour as prd.
sku_tier = "Standard"

system_node_count = 2

apps_min_count = 2
apps_max_count = 4

monitoring_min_count = 2
monitoring_max_count = 3

tags = {
  managed-by = "terraform"
}
