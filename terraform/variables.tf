variable "workload_name" {
  description = "Name of the workload this cluster serves. Combined with environment to derive the CAF-compliant cluster names via the Azure naming module, and to locate the vended landing zone resource group this deploys into — so it must match the landing zone's key in the azure-landingzone repo's landingzones component. Capped at 8 characters by the Key Vault name length."
  type        = string
  default     = "aks"

  validation {
    condition     = length(var.workload_name) <= 8
    error_message = "workload_name must be 8 characters or fewer. Key Vault names are capped at 24, and this module builds two — \"kv-<workload_name>-<environment>-jump\" and \"-workload\" — the longer of which reaches exactly 24 at 8 characters. Past that the name is truncated, and since a vault name is a global DNS label, a truncated one is both unreadable and more likely to collide with a vault already claimed in another tenant."
  }
}

variable "environment" {
  description = "Deployment environment. Used to derive the default resource name and tag, and to gate environment-specific behaviour."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of \"dev\", \"stg\", or \"prd\"."
  }
}

# No location variable. The region comes from the vended landing zone resource group
# (see data.tf) — a variable here could only ever disagree with the group the
# resources actually live in.

variable "hub_workload" {
  description = "The connectivity component's workload name in the azure-landingzone repo. Used with environment to locate the hub virtual network and the private DNS zones this cluster links to."
  type        = string
  default     = "hub"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster. Pinned for reproducible clusters; bump deliberately (AKS only supports upgrades to newer versions, never downgrades)."
  type        = string
  default     = "1.34.8"
}

# --- system pool (mode System) --------------------------------------------
# Runs cluster-critical add-ons only. Tainted CriticalAddonsOnly=true:NoSchedule
# in main.tf so application workloads land on the apps/monitoring pools instead.

variable "system_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool. Defaults to one per availability zone for zone resilience."
  type        = number
  default     = 3
}

# --- apps pool (mode User) -------------------------------------------------
# Default landing zone for application workloads. Untainted.

variable "apps_vm_size" {
  description = "VM size for the apps node pool."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "apps_min_count" {
  description = "Minimum node count for the autoscaled apps node pool. Defaults to one per availability zone for zone resilience."
  type        = number
  default     = 3
}

variable "apps_max_count" {
  description = "Maximum node count for the autoscaled apps node pool."
  type        = number
  default     = 6
}

# --- monitoring pool (mode User) -------------------------------------------
# Isolated for the observability stack (Prometheus/Grafana/Loki). Tainted
# workload=monitoring:NoSchedule and labelled workload=monitoring in main.tf;
# monitoring workloads must set a matching toleration and nodeSelector.

variable "monitoring_vm_size" {
  description = "VM size for the monitoring node pool."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "monitoring_min_count" {
  description = "Minimum node count for the autoscaled monitoring node pool. Defaults to one per availability zone for zone resilience."
  type        = number
  default     = 3
}

variable "monitoring_max_count" {
  description = "Maximum node count for the autoscaled monitoring node pool."
  type        = number
  default     = 6
}

variable "availability_zones" {
  description = "Availability zones to spread every node pool across. Defaults to all three zones for zone resilience; set to [] to disable zone pinning (regional). The chosen VM size must be available in each listed zone in the target region."
  type        = list(string)
  default     = ["1", "2", "3"]
}

# --- networking -------------------------------------------------------------
# The cluster is private by design: the API server has no public endpoint, and
# is reachable only from inside the VNet or via `az aks command invoke`. See
# network.tf and locals.tf.
#
# The three ranges below must not overlap each other, the VNet, or anything the
# VNet is peered with or routed to. AKS rejects overlaps at create time, which
# is a slow way to find out.
#
# This spoke sits at 10.1.0.0/16 because the hub holds 10.0.0.0/22 and Azure refuses
# to peer virtual networks with overlapping address spaces — the failure is at peering
# creation, not at plan. Keep spokes out of 10.0.0.0/22 and off each other.

variable "vnet_address_space" {
  description = "Address space of the cluster VNet. Must contain node_subnet_address_prefix and api_server_subnet_address_prefix, and must not overlap pod_cidr, service_cidr, or any peered network."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block."
  }
}

variable "node_subnet_address_prefix" {
  description = "Address prefix of the subnet holding the cluster nodes. Azure CNI Overlay places pods on pod_cidr rather than on VNet addresses, so this only has to accommodate the node count plus upgrade surge — not the pod count."
  type        = string
  default     = "10.1.0.0/22"

  validation {
    condition     = can(cidrhost(var.node_subnet_address_prefix, 0))
    error_message = "node_subnet_address_prefix must be a valid CIDR block."
  }
}

variable "api_server_subnet_address_prefix" {
  description = "Address prefix of the subnet the API server is projected into by VNet integration. Delegated to Microsoft.ContainerService/managedClusters and dedicated to the API server; AKS requires /28 or larger."
  type        = string
  default     = "10.1.4.0/28"

  validation {
    condition     = can(cidrhost(var.api_server_subnet_address_prefix, 0))
    error_message = "api_server_subnet_address_prefix must be a valid CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.api_server_subnet_address_prefix)[1]) <= 28
    error_message = "api_server_subnet_address_prefix must be /28 or larger — AKS rejects a smaller API server subnet."
  }
}

variable "pod_cidr" {
  description = "Address range pods are allocated from under Azure CNI Overlay. Routed only inside the cluster, so it never consumes VNet addresses; defaults to CGNAT space to keep it clear of RFC1918 networks the VNet might peer with."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR block."
  }
}

variable "service_cidr" {
  description = "Address range Kubernetes ClusterIP services are allocated from. Virtual to the cluster and never routed on the VNet, but must still not overlap it. The kube-dns service IP is derived from this as its tenth address."
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 10))
    error_message = "service_cidr must be a valid CIDR block with room for at least ten addresses."
  }
}

variable "privatelink_subnet_address_prefix" {
  description = "Address prefix of the subnet holding private endpoints. Must sit inside vnet_address_space and not overlap the node, API server, or jump box subnets. Inert unless workload_key_vault_enabled is true — nothing else in this module takes a private endpoint yet."
  type        = string
  default     = "10.1.6.0/28"

  validation {
    condition     = can(cidrhost(var.privatelink_subnet_address_prefix, 0))
    error_message = "privatelink_subnet_address_prefix must be a valid CIDR block."
  }
}

# --- workload Key Vault -----------------------------------------------------
# Application secrets, behind a private endpoint. See main.keyvault.tf.

variable "workload_key_vault_enabled" {
  description = "Whether to create the workload Key Vault, its private endpoint, the privatelink.vaultcore.azure.net private DNS zone, and the subnet and NSG that host the endpoint. The vault has no public endpoint, so its data plane is reachable only from the VNet — via the jump box, a peered network, or the Key Vault CSI driver. Set to false in a hub-and-spoke landing zone where the DNS zone is owned centrally, since a VNet can link to only one zone of a given name."
  type        = bool
  default     = true
}

variable "workload_key_vault_secrets_users" {
  description = "Principal IDs to grant \"Key Vault Secrets User\" on the workload Key Vault — read-only access to secret values. This is where a workload identity goes: the object ID of the user-assigned identity federated to the Kubernetes service account that mounts secrets through the Key Vault CSI driver. Empty by default, which leaves only the deploying identity able to manage the vault. Inert unless workload_key_vault_enabled is true."
  type        = list(string)
  default     = []
}

variable "loki_retention_days" {
  description = "How long Loki keeps log chunks before its compactor deletes them. The blob account is billed on what is stored, so this is the only thing bounding that bill — Loki's own default is to keep everything forever. Applied by the compactor in gitops/infrastructure/controllers/loki.yaml, which reads it as the LOKI_RETENTION_PERIOD substitution (this number with a \"d\" appended), not by a lifecycle rule on the account: Loki has to delete its index entries in the same pass, and a rule that expired chunks underneath it would leave the index pointing at blobs that no longer exist."
  type        = number
  default     = 14

  validation {
    condition     = var.loki_retention_days >= 1 && var.loki_retention_days <= 365
    error_message = "loki_retention_days must be between 1 and 365."
  }
}

# --- tenant workload identities ---------------------------------------------
# One user-assigned identity per tenant workload, federated to the Kubernetes
# service account it runs as. See main.tenants.tf.

variable "workload_identities" {
  description = "Tenant workloads that authenticate to Azure with workload identity, keyed by tenant name. Each entry creates a user-assigned identity named \"id-<workload_name>-<environment>-<key>\" and a federated identity credential binding it to \"system:serviceaccount:<namespace>:<service_account>\" on this cluster's OIDC issuer, and — unless key_vault_secrets_user is false — grants it \"Key Vault Secrets User\" on the workload Key Vault. Empty by default: no tenant, no identity, no grant, which is what keeps the private vault's grant list short. The namespace and service account must match the manifests in gitops/ exactly. A mismatch is neither a plan nor an apply failure; it is an AADSTS70021 \"no matching federated identity record found\" the first time the pod asks Entra ID for a token."
  type = map(object({
    namespace              = string
    service_account        = string
    key_vault_secrets_user = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for key in keys(var.workload_identities) :
      can(regex("^[a-z0-9]([-a-z0-9]{0,22}[a-z0-9])?$", key))
    ])
    error_message = "each workload_identities key must be a lowercase DNS label of 24 characters or fewer — the key becomes both the suffix of a user-assigned identity name and, uppercased, a Flux post-build substitution variable, and neither tolerates other characters."
  }

  validation {
    condition = alltrue(flatten([
      for identity in values(var.workload_identities) : [
        can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", identity.namespace)),
        can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", identity.service_account)),
      ]
    ]))
    error_message = "workload_identities namespace and service_account must each be a lowercase RFC1123 DNS label — they are written verbatim into a federated credential subject of the form \"system:serviceaccount:<namespace>:<service_account>\", which Entra ID matches by exact string and never normalises."
  }
}

# --- jump box ---------------------------------------------------------------
# The administrative path into the private cluster. See main.jumpbox.tf.

variable "jumpbox_enabled" {
  description = "Whether to create the jump box and its subnet. Turning this off leaves the cluster reachable only through `az aks command invoke` or a network path added elsewhere, so make sure one exists first."
  type        = bool
  default     = true
}

variable "jumpbox_subnet_address_prefix" {
  description = "Address prefix of the jump box subnet. Sized for a single VM; must sit inside vnet_address_space and not overlap the node or API server subnets."
  type        = string
  default     = "10.1.5.0/28"

  validation {
    condition     = can(cidrhost(var.jumpbox_subnet_address_prefix, 0))
    error_message = "jumpbox_subnet_address_prefix must be a valid CIDR block."
  }
}

variable "jumpbox_vm_size" {
  description = "VM size for the jump box. It spends most of its life idle, so deallocate it when unused — compute stops billing, the disk does not, and the Windows Server licence is charged per vCPU for every hour it runs. A burstable B-series would suit the workload better, but the whole B family returns NotAvailableForSubscription on this subscription. Two vCPUs is the floor for a licence charge; the memory-fuller D2as_v6 over the cheaper D2als_v6 because a desktop running Edge in the 4 GiB the \"als\" sizes carry is unusable. Must be a Generation 2 size — the image is Gen2-only."
  type        = string
  default     = "Standard_D2as_v6"
}

variable "jumpbox_secret_expiry_date" {
  description = "Optional RFC3339 expiry for the jump box administrator password secret, e.g. \"2027-01-01T00:00:00Z\". Null by default: Key Vault refuses to serve an expired secret, so a date nobody is watching locks everyone out of the only route into the cluster. Note that an expiry here lapses the copy in the vault, not the password on the VM — the two only stay in step if the date is met by a rotation, which is a replace of random_password.jumpbox_admin, not a re-apply."
  type        = string
  default     = null

  validation {
    condition     = var.jumpbox_secret_expiry_date == null || can(formatdate("YYYY-MM-DD", var.jumpbox_secret_expiry_date))
    error_message = "jumpbox_secret_expiry_date must be an RFC3339 timestamp, e.g. \"2027-01-01T00:00:00Z\"."
  }
}

variable "jumpbox_key_vault_allowed_ip_ranges" {
  description = "Public IPv4 addresses or CIDR ranges allowed to reach the jump box Key Vault's data plane, on top of RBAC. Empty by default, which leaves the vault reachable from anywhere and RBAC as the only guard — the behaviour before this variable existed. Setting it switches the vault to default-deny. Whoever runs Terraform must be in this list: the secret is written over the data plane, so an apply from an address that is not listed fails with a 403 Forbidden, and a GitHub-hosted runner's egress address is not stable enough to list. Azure rejects RFC1918 ranges and IPv6 here, and the firewall governs the data plane only — the vault's own configuration stays reachable through ARM, so locking yourself out is recoverable by clearing this and re-applying."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for range in var.jumpbox_key_vault_allowed_ip_ranges :
      can(regex("^(\\d{1,3}\\.){3}\\d{1,3}(/(3[0-2]|[12]?\\d))?$", range))
    ])
    error_message = "each entry must be an IPv4 address or CIDR range, e.g. \"203.0.113.4\" or \"203.0.113.0/24\". Key Vault supports IPv4 only."
  }

  validation {
    condition = alltrue([
      for range in var.jumpbox_key_vault_allowed_ip_ranges :
      !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2\\d|3[01])\\.)", range))
    ])
    error_message = "Key Vault IP rules accept public addresses only — Azure rejects the RFC1918 private ranges (10.x, 172.16-31.x, 192.168.x). To admit traffic from inside the VNet, use a service endpoint or private endpoint rather than an IP rule."
  }
}

variable "bastion_enabled" {
  description = "Whether to create the Azure Bastion host that fronts the jump box. The Developer SKU is free and needs no dedicated subnet, but is not offered in every region — set this to false where the landing zone's region does not support it. Inert unless jumpbox_enabled is true."
  type        = bool
  default     = true
}

variable "sku_tier" {
  description = "AKS control plane pricing tier. One of \"Free\", \"Standard\", or \"Premium\". Standard adds the financially-backed API server uptime SLA — recommended for zone-resilient/production clusters."
  type        = string
  default     = "Standard"
}

# --- upgrades and maintenance ----------------------------------------------
# Two independent auto-upgrade channels — node OS image and Kubernetes version —
# each gated by its own maintenance window.

variable "node_os_upgrade_channel" {
  description = "How node OS updates are applied. \"NodeImage\" upgrades to the latest AKS-validated node image; \"SecurityPatch\" applies OS security patches in place; \"Unmanaged\" leaves patching to the OS's own updater; \"None\" disables it. Constrained to node_os_maintenance_window."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be one of \"NodeImage\", \"SecurityPatch\", \"Unmanaged\", or \"None\"."
  }
}

variable "kubernetes_upgrade_channel" {
  description = "Auto-upgrade channel for the Kubernetes version itself. Defaults to \"none\" because var.kubernetes_version is pinned — anything else lets AKS move the version out from under Terraform, which then reports drift on every plan. Enable only alongside unpinning kubernetes_version. When not \"none\", cluster_maintenance_window applies."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "patch", "stable", "rapid", "node-image"], var.kubernetes_upgrade_channel)
    error_message = "kubernetes_upgrade_channel must be one of \"none\", \"patch\", \"stable\", \"rapid\", or \"node-image\"."
  }
}

variable "node_os_maintenance_window" {
  description = "When node OS updates are allowed to run. Defaults to a daily 4-hour window from 19:00 UTC. Times are in UTC unless utc_offset says otherwise; duration_hours must be 4-24. start_date is the date the window becomes active and must not be null — see the note in locals.tf."
  type = object({
    start_time     = optional(string, "19:00")
    duration_hours = optional(number, 4)
    interval_days  = optional(number, 1)
    utc_offset     = optional(string, "+00:00")
    start_date     = optional(string, "2024-01-01")
  })
  default = {}

  validation {
    condition     = var.node_os_maintenance_window.duration_hours >= 4 && var.node_os_maintenance_window.duration_hours <= 24
    error_message = "node_os_maintenance_window.duration_hours must be between 4 and 24."
  }

  validation {
    condition     = var.node_os_maintenance_window.start_date != null && can(formatdate("YYYY-MM-DD", "${var.node_os_maintenance_window.start_date}T00:00:00Z"))
    error_message = "node_os_maintenance_window.start_date must be a YYYY-MM-DD date and cannot be null — AKS fills a null start date in itself, which leaves a diff on every plan."
  }
}

variable "cluster_maintenance_window" {
  description = "When Kubernetes version auto-upgrades are allowed to run. Inert unless kubernetes_upgrade_channel is set to something other than \"none\". Defaults to a weekly 4-hour window from 06:00 UTC on Sunday, clear of the daily node OS window; duration_hours must be 4-24. start_date is the date the window becomes active and must not be null — see the note in locals.tf."
  type = object({
    day_of_week    = optional(string, "Sunday")
    start_time     = optional(string, "06:00")
    duration_hours = optional(number, 4)
    interval_weeks = optional(number, 1)
    utc_offset     = optional(string, "+00:00")
    start_date     = optional(string, "2024-01-01")
  })
  default = {}

  validation {
    condition     = var.cluster_maintenance_window.duration_hours >= 4 && var.cluster_maintenance_window.duration_hours <= 24
    error_message = "cluster_maintenance_window.duration_hours must be between 4 and 24."
  }

  validation {
    condition     = contains(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"], var.cluster_maintenance_window.day_of_week)
    error_message = "cluster_maintenance_window.day_of_week must be a full English day name, e.g. \"Sunday\"."
  }

  validation {
    condition     = var.cluster_maintenance_window.start_date != null && can(formatdate("YYYY-MM-DD", "${var.cluster_maintenance_window.start_date}T00:00:00Z"))
    error_message = "cluster_maintenance_window.start_date must be a YYYY-MM-DD date and cannot be null — AKS fills a null start date in itself, which leaves a diff on every plan."
  }
}

# --- GitOps (Flux) ----------------------------------------------------------
# Flux v2 arrives as the AKS microsoft.flux cluster extension, so it is installed
# and upgraded through ARM rather than against the private API server. See flux.tf.

variable "flux_enabled" {
  description = "Whether to install the Flux v2 (microsoft.flux) cluster extension. On its own this only installs the controllers; set flux_git_repository_url to give them something to reconcile."
  type        = bool
  default     = true
}

variable "flux_git_repository_url" {
  description = "Repository Flux reconciles the cluster from, e.g. \"https://github.com/org/repo.git\" or \"ssh://git@github.com/org/repo.git\". Null by default, which leaves the controllers installed but idle — a legitimate state if the GitRepository is created out-of-band. Inert unless flux_enabled is true. The git host must be reachable from the node subnet."
  type        = string
  default     = null

  validation {
    condition     = var.flux_git_repository_url == null || can(regex("^(https://|ssh://|git@)", var.flux_git_repository_url))
    error_message = "flux_git_repository_url must be an \"https://\", \"ssh://\", or \"git@\" URL."
  }
}

variable "flux_git_branch" {
  description = "Branch of flux_git_repository_url to track. Tags and commits are not exposed as inputs — a cluster that tracks a moving branch is the usual GitOps arrangement."
  type        = string
  default     = "main"
}

variable "flux_git_path" {
  description = "Path inside flux_git_repository_url the cluster's bootstrap Kustomization builds from. Null by default, which derives \"gitops/clusters/<environment>\" — the layout this repository carries, where one repository serves all three clusters. Set it only when pointing flux_git_repository_url at a repository with a different tree. A path that does not exist is neither a plan nor an apply failure: ARM accepts it and the Kustomization then reports NotReady inside a cluster with no public API server."
  type        = string
  default     = null
}

variable "flux_sync_interval_seconds" {
  description = "How often Flux polls the repository and re-applies the Kustomization. The floor is 30 seconds; shorter intervals mostly generate git host traffic, and a push-based webhook is the better answer if 60 seconds is too slow."
  type        = number
  default     = 60

  validation {
    condition     = var.flux_sync_interval_seconds >= 30
    error_message = "flux_sync_interval_seconds must be at least 30."
  }
}

variable "flux_git_credentials" {
  description = "Credentials for a private repository, in their natural form — this module base64-encodes them for the ARM API. Empty by default, which is what a public repository needs. Use either the HTTPS pair (https_user with a PAT as https_key) or the SSH pair (ssh_private_key as a PEM, with ssh_known_hosts in known_hosts format), never both. These land in state; keep the backend encrypted and access-controlled."
  type = object({
    https_user      = optional(string)
    https_key       = optional(string)
    ssh_private_key = optional(string)
    ssh_known_hosts = optional(string)
  })
  default   = {}
  sensitive = true

  validation {
    condition = !(
      (var.flux_git_credentials.https_user != null || var.flux_git_credentials.https_key != null) &&
      var.flux_git_credentials.ssh_private_key != null
    )
    error_message = "flux_git_credentials must carry HTTPS or SSH credentials, not both — the ARM API rejects a git repository configured with each."
  }

  validation {
    condition     = (var.flux_git_credentials.https_user == null) == (var.flux_git_credentials.https_key == null)
    error_message = "flux_git_credentials.https_user and flux_git_credentials.https_key must be set together."
  }

  validation {
    condition     = var.flux_git_credentials.ssh_private_key == null || var.flux_git_credentials.ssh_known_hosts != null
    error_message = "flux_git_credentials.ssh_known_hosts must be set alongside ssh_private_key — Flux verifies the host key and the sync fails without it."
  }
}

variable "apps_dns_zone_suffix" {
  description = "Suffix of the private DNS zone serving the hostnames this cluster publishes. The environment is prepended to it, so \"apps.internal\" gives dev.apps.internal — see local.apps_dns_zone_name. The zone is created in the landing zone's resource group and linked to this VNet, and external-dns writes a record into it per HTTPRoute hostname. Null skips the zone and the external-dns identity with it, which leaves hosts entries on the jump box as the only way to resolve those names."
  type        = string
  default     = "apps.internal"

  validation {
    condition     = var.apps_dns_zone_suffix == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.apps_dns_zone_suffix))
    error_message = "apps_dns_zone_suffix must be a lowercase DNS name with at least two labels, e.g. \"apps.internal\"."
  }

  validation {
    condition     = var.apps_dns_zone_suffix == null || !endswith(var.apps_dns_zone_suffix, ".local")
    error_message = "apps_dns_zone_suffix must not end in \".local\" — it is reserved for mDNS and resolves unpredictably on clients that implement it."
  }
}

# Authentication and authorization take no inputs by design — Entra ID with Azure
# RBAC, local accounts off, workload identity on. See locals.tf and main.tf.

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
