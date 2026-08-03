# Terraform module

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_aks"></a> [aks](#module\_aks) | Azure/avm-res-containerservice-managedcluster/azurerm | ~> 0.6 |
| <a name="module_aks_identity"></a> [aks\_identity](#module\_aks\_identity) | Azure/avm-res-managedidentity-userassignedidentity/azurerm | ~> 0.5 |
| <a name="module_bastion"></a> [bastion](#module\_bastion) | Azure/avm-res-network-bastionhost/azurerm | ~> 0.9 |
| <a name="module_jumpbox"></a> [jumpbox](#module\_jumpbox) | Azure/avm-res-compute-virtualmachine/azurerm | ~> 0.21 |
| <a name="module_jumpbox_key_vault"></a> [jumpbox\_key\_vault](#module\_jumpbox\_key\_vault) | Azure/avm-res-keyvault-vault/azurerm | ~> 0.10 |
| <a name="module_key_vault_private_dns_zone"></a> [key\_vault\_private\_dns\_zone](#module\_key\_vault\_private\_dns\_zone) | Azure/avm-res-network-privatednszone/azurerm | ~> 0.5 |
| <a name="module_naming"></a> [naming](#module\_naming) | Azure/naming/azurerm | ~> 0.4 |
| <a name="module_nsg_api_server"></a> [nsg\_api\_server](#module\_nsg\_api\_server) | Azure/avm-res-network-networksecuritygroup/azurerm | ~> 0.5 |
| <a name="module_nsg_jumpbox"></a> [nsg\_jumpbox](#module\_nsg\_jumpbox) | Azure/avm-res-network-networksecuritygroup/azurerm | ~> 0.5 |
| <a name="module_nsg_nodes"></a> [nsg\_nodes](#module\_nsg\_nodes) | Azure/avm-res-network-networksecuritygroup/azurerm | ~> 0.5 |
| <a name="module_nsg_privatelink"></a> [nsg\_privatelink](#module\_nsg\_privatelink) | Azure/avm-res-network-networksecuritygroup/azurerm | ~> 0.5 |
| <a name="module_resource_group"></a> [resource\_group](#module\_resource\_group) | Azure/avm-res-resources-resourcegroup/azurerm | ~> 0.4 |
| <a name="module_vnet"></a> [vnet](#module\_vnet) | Azure/avm-res-network-virtualnetwork/azurerm | ~> 0.20 |
| <a name="module_workload_key_vault"></a> [workload\_key\_vault](#module\_workload\_key\_vault) | Azure/avm-res-keyvault-vault/azurerm | ~> 0.10 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_kubernetes_cluster_extension.flux](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_extension) | resource |
| [azurerm_kubernetes_flux_configuration.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_flux_configuration) | resource |
| [tls_private_key.jumpbox_admin](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_server_subnet_address_prefix"></a> [api\_server\_subnet\_address\_prefix](#input\_api\_server\_subnet\_address\_prefix) | Address prefix of the subnet the API server is projected into by VNet integration. Delegated to Microsoft.ContainerService/managedClusters and dedicated to the API server; AKS requires /28 or larger. | `string` | `"10.0.4.0/28"` | no |
| <a name="input_apps_max_count"></a> [apps\_max\_count](#input\_apps\_max\_count) | Maximum node count for the autoscaled apps node pool. | `number` | `6` | no |
| <a name="input_apps_min_count"></a> [apps\_min\_count](#input\_apps\_min\_count) | Minimum node count for the autoscaled apps node pool. Defaults to one per availability zone for zone resilience. | `number` | `3` | no |
| <a name="input_apps_vm_size"></a> [apps\_vm\_size](#input\_apps\_vm\_size) | VM size for the apps node pool. | `string` | `"Standard_D2s_v6"` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones to spread every node pool across. Defaults to all three zones for zone resilience; set to [] to disable zone pinning (regional). The chosen VM size must be available in each listed zone in the target region. | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_bastion_enabled"></a> [bastion\_enabled](#input\_bastion\_enabled) | Whether to create the Azure Bastion host that fronts the jump box. The Developer SKU is free and needs no dedicated subnet, but is not offered in every region — set this to false where var.location does not support it. Inert unless jumpbox\_enabled is true. | `bool` | `true` | no |
| <a name="input_cluster_maintenance_window"></a> [cluster\_maintenance\_window](#input\_cluster\_maintenance\_window) | When Kubernetes version auto-upgrades are allowed to run. Inert unless kubernetes\_upgrade\_channel is set to something other than "none". Defaults to a weekly 4-hour window from 06:00 UTC on Sunday, clear of the daily node OS window; duration\_hours must be 4-24. start\_date is the date the window becomes active and must not be null — see the note in locals.tf. | <pre>object({<br/>    day_of_week    = optional(string, "Sunday")<br/>    start_time     = optional(string, "06:00")<br/>    duration_hours = optional(number, 4)<br/>    interval_weeks = optional(number, 1)<br/>    utc_offset     = optional(string, "+00:00")<br/>    start_date     = optional(string, "2024-01-01")<br/>  })</pre> | `{}` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Used to derive the default resource name and tag, and to gate environment-specific behaviour. | `string` | `"dev"` | no |
| <a name="input_flux_enabled"></a> [flux\_enabled](#input\_flux\_enabled) | Whether to install the Flux v2 (microsoft.flux) cluster extension. On its own this only installs the controllers; set flux\_git\_repository\_url to give them something to reconcile. | `bool` | `true` | no |
| <a name="input_flux_git_branch"></a> [flux\_git\_branch](#input\_flux\_git\_branch) | Branch of flux\_git\_repository\_url to track. Tags and commits are not exposed as inputs — a cluster that tracks a moving branch is the usual GitOps arrangement. | `string` | `"main"` | no |
| <a name="input_flux_git_credentials"></a> [flux\_git\_credentials](#input\_flux\_git\_credentials) | Credentials for a private repository, in their natural form — this module base64-encodes them for the ARM API. Empty by default, which is what a public repository needs. Use either the HTTPS pair (https\_user with a PAT as https\_key) or the SSH pair (ssh\_private\_key as a PEM, with ssh\_known\_hosts in known\_hosts format), never both. These land in state; keep the backend encrypted and access-controlled. | <pre>object({<br/>    https_user      = optional(string)<br/>    https_key       = optional(string)<br/>    ssh_private_key = optional(string)<br/>    ssh_known_hosts = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_flux_git_path"></a> [flux\_git\_path](#input\_flux\_git\_path) | Path inside the repository the cluster's Kustomization builds from, e.g. "clusters/dev". Null by default, which builds from the repository root — set it for the common layout where one repository serves several clusters. Flux fails to reconcile if the path does not exist. | `string` | `null` | no |
| <a name="input_flux_git_repository_url"></a> [flux\_git\_repository\_url](#input\_flux\_git\_repository\_url) | Repository Flux reconciles the cluster from, e.g. "https://github.com/org/repo.git" or "ssh://git@github.com/org/repo.git". Null by default, which leaves the controllers installed but idle — a legitimate state if the GitRepository is created out-of-band. Inert unless flux\_enabled is true. The git host must be reachable from the node subnet. | `string` | `null` | no |
| <a name="input_flux_sync_interval_seconds"></a> [flux\_sync\_interval\_seconds](#input\_flux\_sync\_interval\_seconds) | How often Flux polls the repository and re-applies the Kustomization. The floor is 30 seconds; shorter intervals mostly generate git host traffic, and a push-based webhook is the better answer if 60 seconds is too slow. | `number` | `60` | no |
| <a name="input_jumpbox_enabled"></a> [jumpbox\_enabled](#input\_jumpbox\_enabled) | Whether to create the jump box and its subnet. Turning this off leaves the cluster reachable only through `az aks command invoke` or a network path added elsewhere, so make sure one exists first. | `bool` | `true` | no |
| <a name="input_jumpbox_key_expiry_date"></a> [jumpbox\_key\_expiry\_date](#input\_jumpbox\_key\_expiry\_date) | Optional RFC3339 expiry for the jump box SSH key secret, e.g. "2027-01-01T00:00:00Z". Null by default: Key Vault refuses to serve an expired secret, so a date nobody is watching locks everyone out of the only route into the cluster. Set it once a rotation process exists to meet it — rotation is a replace of tls\_private\_key.jumpbox\_admin, not a re-apply. | `string` | `null` | no |
| <a name="input_jumpbox_subnet_address_prefix"></a> [jumpbox\_subnet\_address\_prefix](#input\_jumpbox\_subnet\_address\_prefix) | Address prefix of the jump box subnet. Sized for a single VM; must sit inside vnet\_address\_space and not overlap the node or API server subnets. | `string` | `"10.0.5.0/28"` | no |
| <a name="input_jumpbox_vm_size"></a> [jumpbox\_vm\_size](#input\_jumpbox\_vm\_size) | VM size for the jump box. Burstable by default — it spends most of its life idle, and the work it does (kubectl, helm, az) is interactive rather than sustained. Deallocate it when unused; compute stops billing, the disk does not. | `string` | `"Standard_B2s_v2"` | no |
| <a name="input_kubernetes_upgrade_channel"></a> [kubernetes\_upgrade\_channel](#input\_kubernetes\_upgrade\_channel) | Auto-upgrade channel for the Kubernetes version itself. Defaults to "none" because var.kubernetes\_version is pinned — anything else lets AKS move the version out from under Terraform, which then reports drift on every plan. Enable only alongside unpinning kubernetes\_version. When not "none", cluster\_maintenance\_window applies. | `string` | `"none"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for the cluster. Pinned for reproducible clusters; bump deliberately (AKS only supports upgrades to newer versions, never downgrades). | `string` | `"1.34.8"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region to deploy into. | `string` | `"westeurope"` | no |
| <a name="input_monitoring_max_count"></a> [monitoring\_max\_count](#input\_monitoring\_max\_count) | Maximum node count for the autoscaled monitoring node pool. | `number` | `6` | no |
| <a name="input_monitoring_min_count"></a> [monitoring\_min\_count](#input\_monitoring\_min\_count) | Minimum node count for the autoscaled monitoring node pool. Defaults to one per availability zone for zone resilience. | `number` | `3` | no |
| <a name="input_monitoring_vm_size"></a> [monitoring\_vm\_size](#input\_monitoring\_vm\_size) | VM size for the monitoring node pool. | `string` | `"Standard_D2s_v6"` | no |
| <a name="input_node_os_maintenance_window"></a> [node\_os\_maintenance\_window](#input\_node\_os\_maintenance\_window) | When node OS updates are allowed to run. Defaults to a daily 4-hour window from 19:00 UTC. Times are in UTC unless utc\_offset says otherwise; duration\_hours must be 4-24. start\_date is the date the window becomes active and must not be null — see the note in locals.tf. | <pre>object({<br/>    start_time     = optional(string, "19:00")<br/>    duration_hours = optional(number, 4)<br/>    interval_days  = optional(number, 1)<br/>    utc_offset     = optional(string, "+00:00")<br/>    start_date     = optional(string, "2024-01-01")<br/>  })</pre> | `{}` | no |
| <a name="input_node_os_upgrade_channel"></a> [node\_os\_upgrade\_channel](#input\_node\_os\_upgrade\_channel) | How node OS updates are applied. "NodeImage" upgrades to the latest AKS-validated node image; "SecurityPatch" applies OS security patches in place; "Unmanaged" leaves patching to the OS's own updater; "None" disables it. Constrained to node\_os\_maintenance\_window. | `string` | `"NodeImage"` | no |
| <a name="input_node_subnet_address_prefix"></a> [node\_subnet\_address\_prefix](#input\_node\_subnet\_address\_prefix) | Address prefix of the subnet holding the cluster nodes. Azure CNI Overlay places pods on pod\_cidr rather than on VNet addresses, so this only has to accommodate the node count plus upgrade surge — not the pod count. | `string` | `"10.0.0.0/22"` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Address range pods are allocated from under Azure CNI Overlay. Routed only inside the cluster, so it never consumes VNet addresses; defaults to CGNAT space to keep it clear of RFC1918 networks the VNet might peer with. | `string` | `"100.64.0.0/16"` | no |
| <a name="input_privatelink_subnet_address_prefix"></a> [privatelink\_subnet\_address\_prefix](#input\_privatelink\_subnet\_address\_prefix) | Address prefix of the subnet holding private endpoints. Must sit inside vnet\_address\_space and not overlap the node, API server, or jump box subnets. Inert unless workload\_key\_vault\_enabled is true — nothing else in this module takes a private endpoint yet. | `string` | `"10.0.6.0/28"` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | Address range Kubernetes ClusterIP services are allocated from. Virtual to the cluster and never routed on the VNet, but must still not overlap it. The kube-dns service IP is derived from this as its tenth address. | `string` | `"172.16.0.0/16"` | no |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | AKS control plane pricing tier. One of "Free", "Standard", or "Premium". Standard adds the financially-backed API server uptime SLA — recommended for zone-resilient/production clusters. | `string` | `"Standard"` | no |
| <a name="input_system_node_count"></a> [system\_node\_count](#input\_system\_node\_count) | Number of nodes in the system node pool. Defaults to one per availability zone for zone resilience. | `number` | `3` | no |
| <a name="input_system_vm_size"></a> [system\_vm\_size](#input\_system\_vm\_size) | VM size for the system node pool. | `string` | `"Standard_D2s_v6"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to created resources. | `map(string)` | `{}` | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address space of the cluster VNet. Must contain node\_subnet\_address\_prefix and api\_server\_subnet\_address\_prefix, and must not overlap pod\_cidr, service\_cidr, or any peered network. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_workload_key_vault_enabled"></a> [workload\_key\_vault\_enabled](#input\_workload\_key\_vault\_enabled) | Whether to create the workload Key Vault, its private endpoint, the privatelink.vaultcore.azure.net private DNS zone, and the subnet and NSG that host the endpoint. The vault has no public endpoint, so its data plane is reachable only from the VNet — via the jump box, a peered network, or the Key Vault CSI driver. Set to false in a hub-and-spoke landing zone where the DNS zone is owned centrally, since a VNet can link to only one zone of a given name. | `bool` | `true` | no |
| <a name="input_workload_key_vault_secrets_users"></a> [workload\_key\_vault\_secrets\_users](#input\_workload\_key\_vault\_secrets\_users) | Principal IDs to grant "Key Vault Secrets User" on the workload Key Vault — read-only access to secret values. This is where a workload identity goes: the object ID of the user-assigned identity federated to the Kubernetes service account that mounts secrets through the Key Vault CSI driver. Empty by default, which leaves only the deploying identity able to manage the vault. Inert unless workload\_key\_vault\_enabled is true. | `list(string)` | `[]` | no |
| <a name="input_workload_name"></a> [workload\_name](#input\_workload\_name) | Name of the workload this cluster serves. Combined with environment to derive the CAF-compliant cluster and resource group names via the Azure naming module. Capped at 9 characters by the Key Vault name length. | `string` | `"main"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_server_subnet_id"></a> [api\_server\_subnet\_id](#output\_api\_server\_subnet\_id) | Resource ID of the subnet the API server is projected into by VNet integration. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Resource ID of the AKS cluster. |
| <a name="output_cluster_identity_principal_id"></a> [cluster\_identity\_principal\_id](#output\_cluster\_identity\_principal\_id) | Principal ID of the user-assigned identity the cluster control plane runs as. Grant this rights on resources the control plane itself must reach, not workloads — those should use workload identity via oidc\_issuer\_url. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the AKS cluster. |
| <a name="output_flux_configuration_id"></a> [flux\_configuration\_id](#output\_flux\_configuration\_id) | Resource ID of the Flux configuration reconciling the cluster, or null when no flux\_git\_repository\_url is set. Null here with a non-null flux\_extension\_id means Flux is installed but syncing nothing. |
| <a name="output_flux_extension_id"></a> [flux\_extension\_id](#output\_flux\_extension\_id) | Resource ID of the microsoft.flux cluster extension, or null when flux\_enabled is false. |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | FQDN of the AKS cluster API server. |
| <a name="output_jumpbox_id"></a> [jumpbox\_id](#output\_jumpbox\_id) | Resource ID of the jump box VM, or null when jumpbox\_enabled is false. Use as the scope when granting operators "Virtual Machine Administrator Login". |
| <a name="output_jumpbox_key_vault_name"></a> [jumpbox\_key\_vault\_name](#output\_jumpbox\_key\_vault\_name) | Name of the Key Vault holding the jump box SSH private key, or null when jumpbox\_enabled is false. Select this vault in the Bastion connection pane. |
| <a name="output_jumpbox_private_ip"></a> [jumpbox\_private\_ip](#output\_jumpbox\_private\_ip) | Private IP of the jump box, or null when jumpbox\_enabled is false. Informational — connect through Bastion rather than to this address. |
| <a name="output_jumpbox_ssh_secret_name"></a> [jumpbox\_ssh\_secret\_name](#output\_jumpbox\_ssh\_secret\_name) | Name of the Key Vault secret holding the jump box SSH private key. Connect with authentication type "SSH Private Key from Azure Key Vault" and username "azureuser". |
| <a name="output_key_vault_private_dns_zone_id"></a> [key\_vault\_private\_dns\_zone\_id](#output\_key\_vault\_private\_dns\_zone\_id) | Resource ID of the privatelink.vaultcore.azure.net private DNS zone, or null when workload\_key\_vault\_enabled is false. Link a peered VNet to this zone so clients there resolve the vault to its private endpoint. |
| <a name="output_node_resource_group_name"></a> [node\_resource\_group\_name](#output\_node\_resource\_group\_name) | Name of the auto-generated resource group holding the cluster's node resources. |
| <a name="output_node_subnet_id"></a> [node\_subnet\_id](#output\_node\_subnet\_id) | Resource ID of the subnet holding the cluster nodes. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | Issuer URL of the cluster's OIDC endpoint. Required as the issuer when creating the federated identity credential that lets a Kubernetes service account authenticate to Entra ID via workload identity. |
| <a name="output_private_fqdn"></a> [private\_fqdn](#output\_private\_fqdn) | Private FQDN of the API server, served by the AKS-managed private.<region>.azmk8s.io zone. Only resolves from inside the VNet or a network linked to that zone — prefer the fqdn output, which resolves anywhere and points at the same private address. |
| <a name="output_privatelink_subnet_id"></a> [privatelink\_subnet\_id](#output\_privatelink\_subnet\_id) | Resource ID of the subnet holding private endpoints, or null when workload\_key\_vault\_enabled is false. Use as the subnet for further private endpoints rather than adding another subnet. |
| <a name="output_resource_group_id"></a> [resource\_group\_id](#output\_resource\_group\_id) | Resource ID of the resource group containing the AKS cluster. Use as the scope when granting a role over everything this module creates. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group containing the AKS cluster. |
| <a name="output_virtual_network_id"></a> [virtual\_network\_id](#output\_virtual\_network\_id) | Resource ID of the cluster VNet. Use as the remote side when peering, or as the target of a private DNS zone virtual network link. |
| <a name="output_virtual_network_name"></a> [virtual\_network\_name](#output\_virtual\_network\_name) | Name of the cluster VNet. |
| <a name="output_workload_key_vault_id"></a> [workload\_key\_vault\_id](#output\_workload\_key\_vault\_id) | Resource ID of the workload Key Vault, or null when workload\_key\_vault\_enabled is false. Use as the scope when granting a workload identity access outside this module. |
| <a name="output_workload_key_vault_name"></a> [workload\_key\_vault\_name](#output\_workload\_key\_vault\_name) | Name of the workload Key Vault, or null when workload\_key\_vault\_enabled is false. Derived as "kv-<workload\_name>-<environment>-secrets", against the jump box vault's "-jumpbox". |
| <a name="output_workload_key_vault_uri"></a> [workload\_key\_vault\_uri](#output\_workload\_key\_vault\_uri) | Data-plane URI of the workload Key Vault, or null when workload\_key\_vault\_enabled is false. Resolves to the private endpoint's address from inside the VNet and to nothing usable from outside it — this is the value a SecretProviderClass takes as its keyvaultName's vault URI. |
<!-- END_TF_DOCS -->
