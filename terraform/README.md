# Terraform module

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.80.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_aks"></a> [aks](#module\_aks) | Azure/avm-res-containerservice-managedcluster/azurerm | ~> 0.6 |
| <a name="module_naming"></a> [naming](#module\_naming) | Azure/naming/azurerm | ~> 0.4 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps_max_count"></a> [apps\_max\_count](#input\_apps\_max\_count) | Maximum node count for the autoscaled apps node pool. | `number` | `6` | no |
| <a name="input_apps_min_count"></a> [apps\_min\_count](#input\_apps\_min\_count) | Minimum node count for the autoscaled apps node pool. Defaults to one per availability zone for zone resilience. | `number` | `3` | no |
| <a name="input_apps_vm_size"></a> [apps\_vm\_size](#input\_apps\_vm\_size) | VM size for the apps node pool. | `string` | `"Standard_D2s_v6"` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to spread every node pool across. Defaults to all three zones for zone resilience; set to [] to disable zone pinning (regional). The chosen VM size must be available in each listed zone in the target region. | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_cluster_maintenance_window"></a> [cluster\_maintenance\_window](#input\_cluster\_maintenance\_window) | When Kubernetes version auto-upgrades are allowed to run. Inert unless kubernetes\_upgrade\_channel is set to something other than "none". Defaults to a weekly 4-hour window from 06:00 UTC on Sunday, clear of the daily node OS window; duration\_hours must be 4-24. | <pre>object({<br/>    day_of_week    = optional(string, "Sunday")<br/>    start_time     = optional(string, "06:00")<br/>    duration_hours = optional(number, 4)<br/>    interval_weeks = optional(number, 1)<br/>    utc_offset     = optional(string, "+00:00")<br/>  })</pre> | `{}` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Used to derive the default resource name and tag, and to gate environment-specific behaviour. | `string` | `"dev"` | no |
| <a name="input_kubernetes_upgrade_channel"></a> [kubernetes\_upgrade\_channel](#input\_kubernetes\_upgrade\_channel) | Auto-upgrade channel for the Kubernetes version itself. Defaults to "none" because var.kubernetes\_version is pinned — anything else lets AKS move the version out from under Terraform, which then reports drift on every plan. Enable only alongside unpinning kubernetes\_version. When not "none", cluster\_maintenance\_window applies. | `string` | `"none"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for the cluster. Pinned for reproducible clusters; bump deliberately (AKS only supports upgrades to newer versions, never downgrades). | `string` | `"1.34.8"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region to deploy into. | `string` | `"westeurope"` | no |
| <a name="input_monitoring_max_count"></a> [monitoring\_max\_count](#input\_monitoring\_max\_count) | Maximum node count for the autoscaled monitoring node pool. | `number` | `6` | no |
| <a name="input_monitoring_min_count"></a> [monitoring\_min\_count](#input\_monitoring\_min\_count) | Minimum node count for the autoscaled monitoring node pool. Defaults to one per availability zone for zone resilience. | `number` | `3` | no |
| <a name="input_monitoring_vm_size"></a> [monitoring\_vm\_size](#input\_monitoring\_vm\_size) | VM size for the monitoring node pool. | `string` | `"Standard_D2s_v6"` | no |
| <a name="input_node_os_maintenance_window"></a> [node\_os\_maintenance\_window](#input\_node\_os\_maintenance\_window) | When node OS updates are allowed to run. Defaults to a daily 4-hour window from 19:00 UTC. Times are in UTC unless utc\_offset says otherwise; duration\_hours must be 4-24. | <pre>object({<br/>    start_time     = optional(string, "19:00")<br/>    duration_hours = optional(number, 4)<br/>    interval_days  = optional(number, 1)<br/>    utc_offset     = optional(string, "+00:00")<br/>  })</pre> | `{}` | no |
| <a name="input_node_os_upgrade_channel"></a> [node\_os\_upgrade\_channel](#input\_node\_os\_upgrade\_channel) | How node OS updates are applied. "NodeImage" upgrades to the latest AKS-validated node image; "SecurityPatch" applies OS security patches in place; "Unmanaged" leaves patching to the OS's own updater; "None" disables it. Constrained to node\_os\_maintenance\_window. | `string` | `"NodeImage"` | no |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | AKS control plane pricing tier. One of "Free", "Standard", or "Premium". Standard adds the financially-backed API server uptime SLA — recommended for zone-resilient/production clusters. | `string` | `"Standard"` | no |
| <a name="input_system_node_count"></a> [system\_node\_count](#input\_system\_node\_count) | Number of nodes in the system node pool. Defaults to one per availability zone for zone resilience. | `number` | `3` | no |
| <a name="input_system_vm_size"></a> [system\_vm\_size](#input\_system\_vm\_size) | VM size for the system node pool. | `string` | `"Standard_D2s_v6"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to created resources. | `map(string)` | `{}` | no |
| <a name="input_workload_name"></a> [workload\_name](#input\_workload\_name) | Name of the workload this cluster serves. Combined with environment to derive the CAF-compliant cluster and resource group names via the Azure naming module. | `string` | `"main"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Resource ID of the AKS cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the AKS cluster. |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | FQDN of the AKS cluster API server. |
| <a name="output_node_resource_group_name"></a> [node\_resource\_group\_name](#output\_node\_resource\_group\_name) | Name of the auto-generated resource group holding the cluster's node resources. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | Issuer URL of the cluster's OIDC endpoint. Required as the issuer when creating the federated identity credential that lets a Kubernetes service account authenticate to Entra ID via workload identity. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group containing the AKS cluster. |
<!-- END_TF_DOCS -->
