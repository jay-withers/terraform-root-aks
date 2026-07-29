# Staging environment — a scaled-down mirror of production.
# Multi-zone and Standard tier so it exercises the same resilience paths as prd,
# but with lower node counts.

environment = "stg"

system_node_count = 2

apps_min_count = 2
apps_max_count = 4

monitoring_min_count = 2
monitoring_max_count = 3
