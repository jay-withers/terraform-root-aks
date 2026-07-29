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
location    = "westeurope"

availability_zones = ["1", "2", "3"]

sku_tier = "Standard"

system_node_count = 3

apps_min_count = 3
apps_max_count = 6

monitoring_min_count = 3
monitoring_max_count = 6

tags = {
  managed-by = "terraform"
}
