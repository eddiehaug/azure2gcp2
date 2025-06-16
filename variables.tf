variable "project_id" {
  description = "GCP Project ID."
  type        = string
}

variable "region" {
  description = "GCP Region."
  type        = string
}

variable "cluster_name" {
  description = "Name of GKE cluster."
  type        = string
}

variable "description" {
  description = "Description of the GKE cluster."
  type        = string
  default     = "Managed by Terraform"
}

variable "labels" {
  description = "A map of labels to apply to the cluster."
  type        = map(string)
  default     = {} # Corresponds to Azure 'tags'
}

variable "location_type" {
  description = "The GKE cluster location type. Can be 'REGIONAL' or 'ZONAL'."
  type        = string
  default     = "REGIONAL" # Maps Azure 'Paid' tier concept, 'Free' might map to Zonal
  validation {
    condition = contains(["REGIONAL", "ZONAL"], upper(var.location_type))
    error_message = "Location type must be 'REGIONAL' or 'ZONAL'."
  }
}

variable "zone" {
  description = "The GKE cluster zone (required if location_type is ZONAL)."
  type        = string
  default     = null
  validation {
    condition = (var.location_type != "ZONAL" || var.zone != null)
    error_message = "Zone must be specified for ZONAL clusters."
  }
}

variable "release_channel" {
  description = "The release channel of the GKE cluster ('UNSPECIFIED', 'RAPID', 'REGULAR', 'STABLE'). Recommended over explicit version."
  type        = string
  default     = "REGULAR" # Maps Azure 'kubernetes_version' but uses channels
  validation {
    condition = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE"], upper(var.release_channel))
    error_message = "Release channel must be one of 'UNSPECIFIED', 'RAPID', 'REGULAR', 'STABLE'."
  }
}

variable "kubernetes_version" {
 description = "The specific Kubernetes version to use. Leave null to use the version from release_channel."
 type = string
 default = null # If specified, overrides release_channel
}

variable "network" {
  description = "The name or self_link of the VPC network to host the cluster."
  type        = string
}

variable "subnetwork" {
  description = "The name or self_link of the subnetwork to host the cluster nodes."
  type        = string # Corresponds to Azure 'virtual_network.subnets' but assumes one subnet for all nodes for simplicity, or needs expansion.
}

variable "ip_allocation_policy" {
  description = "Configuration for VPC-native (alias IP) cluster. Requires cluster_secondary_range_name and services_secondary_range_name."
  type = object({
    cluster_secondary_range_name  = string
    services_secondary_range_name = string
  })
  default = null # Corresponds to Azure network profile/CIDRs. VPC-native is recommended.
  validation {
    condition = (
      var.ip_allocation_policy == null || (
        var.ip_allocation_policy.cluster_secondary_range_name != null &&
        var.ip_allocation_policy.services_secondary_range_name != null
      )
    )
    error_message = "If ip_allocation_policy is set, cluster_secondary_range_name and services_secondary_range_name must be specified."
  }
}

variable "private_cluster_config" {
  description = "Configuration for a private GKE cluster."
  type = object({
    enable_private_endpoint = bool # Access master from VPC
    enable_private_nodes    = bool # Nodes get private IPs
    master_ipv4_cidr_block  = optional(string) # Optional, auto-allocated if null
  })
  default = null # Corresponds to Azure 'private_cluster_enabled'
  validation {
    condition = (
      var.private_cluster_config == null || (
        var.private_cluster_config.enable_private_endpoint != null &&
        var.private_cluster_config.enable_private_nodes != null
      )
    )
    error_message = "If private_cluster_config is set, enable_private_endpoint and enable_private_nodes must be specified."
  }
}

variable "master_authorized_networks_config" {
  description = "List of CIDR blocks authorized to access the master end point."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [] # Corresponds to Azure 'api_server_authorized_ip_ranges'
}

variable "remove_default_node_pool" {
  description = "Whether to remove the default node pool. Recommended to manage node pools separately."
  type        = bool
  default     = true
}

variable "initial_node_count" {
  description = "The number of nodes to create in the default node pool. Used only if remove_default_node_pool is false."
  type        = number
  default     = 1
  validation {
    condition = (var.remove_default_node_pool || var.initial_node_count > 0)
    error_message = "initial_node_count must be greater than 0 if remove_default_node_pool is false."
  }
}

variable "node_pools" {
  description = "Configuration for additional node pools. Keys are node pool names."
  type = map(object({
    machine_type         = optional(string) # Azure vm_size
    node_locations       = optional(list(string)) # Azure availability_zones (as zones)
    initial_node_count   = optional(number) # If not using autoscaling
    enable_auto_scaling  = optional(bool) # Azure enable_auto_scaling
    min_node_count       = optional(number) # Azure min_count
    max_node_count       = optional(number) # Azure max_count
    max_pods_per_node    = optional(number) # Azure max_pods
    node_labels          = optional(map(string)) # Azure node_labels
    taint                = optional(list(object({ key = string, value = string, effect = string }))) # Azure node_taints
    disk_size_gb         = optional(number) # Azure os_disk_size_gb
    disk_type            = optional(string) # Azure os_disk_type (GCP: pd-standard, pd-ssd)
    image_type           = optional(string) # GCP specific (COS_CONTAINERD, UBUNTU_CONTAINERD, WINDOWS_LTSC_CONTAINERD) - Maps roughly to Azure os_type
    service_account      = optional(string) # GCP specific - Node identity (corresponds to Azure identity concept)
    tags                 = optional(list(string)) # GCP specific - Network tags (corresponds to Azure tags)
    spot                 = optional(bool) # GCP specific - Use Spot VMs (corresponds to Azure priority/spot_max_price)
    upgrade_settings     = optional(object({ max_surge = number, max_unavailable = number })) # Corresponds to Azure max_surge
    # Windows config object is optional, but fields inside are required if object is provided
    windows_node_config  = optional(object({ admin_username = string, admin_password = string })) # Corresponds to Azure windows_profile
    resource_labels      = optional(map(string)) # GCP resource labels (corresponds to Azure tags)
    preemptible          = optional(bool) # GCP specific - Use Preemptible VMs (older Spot)
  }))
  default = {} # Corresponds to Azure 'node_pools' (excluding 'default')
}

variable "node_pool_defaults" {
  description = "Default values for additional node pools."
  type = object({
    machine_type         = string
    node_locations       = list(string)
    initial_node_count   = number
    enable_auto_scaling  = bool
    min_node_count       = number
    max_node_count       = number
    max_pods_per_node    = number
    node_labels          = map(string)
    taint                = list(object({ key = string, value = string, effect = string })))
    disk_size_gb         = number
    disk_type            = string
    image_type           = string
    service_account      = string
    tags                 = list(string)
    spot                 = bool
    upgrade_settings     = object({ max_surge = number, max_unavailable = number })
    # Windows config object is optional, default should be null
    windows_node_config  = object({ admin_username = string, admin_password = string })
    resource_labels      = map(string)
    preemptible          = bool
  })
  default = { # Mapping AKS defaults to GKE equivalents/sensible defaults
    machine_type         = "e2-medium" # Approx. Standard_B2s equivalent
    node_locations       = [] # Should be set based on region/zones or cluster location
    initial_node_count   = 1
    enable_auto_scaling  = false
    min_node_count       = 1
    max_node_count       = 10
    max_pods_per_node    = 110 # Default for VPC-native
    node_labels          = {}
    taint                = []
    disk_size_gb         = 100 # Common default
    disk_type            = "pd-standard"
    image_type           = "COS_CONTAINERD" # Recommended GKE OS
    service_account      = "default" # Use project's default SA by default (corresponds to Azure identity concept)
    tags                 = []
    spot                 = false
    upgrade_settings     = { max_surge = 1, max_unavailable = 0 } # Rolling upgrades
    windows_node_config  = null # Default to null object for Windows
    resource_labels      = {}
    preemptible          = false # Spot is preferred over preemptible
  }
}

# Azure default node pool name concept isn't strictly needed if managing
# all node pools via google_container_node_pool resources.

# Azure Identity/RBAC mapping
variable "node_service_account" {
  description = "Email of the service account to be used by the GKE nodes if not specified in node_pool_defaults or node_pools. Defaults to the Compute Engine default service account."
  type        = string
  default     = "default" # Corresponds to Azure identity concept
}

variable "google_group_for_rbac" {
  description = "Google Group email address whose members should be granted cluster admin privileges via ABAC. Note: ABAC is legacy. Consider GKE Identity Service or Workload Identity for modern RBAC."
  type        = string
  default     = null # Corresponds to Azure RBAC/AD Integration
}

variable "enable_network_policy" {
  description = "Whether to enable the network policy addon."
  type        = bool
  default     = false # Corresponds to Azure 'network_policy'
}

variable "enable_policy_controller" {
  description = "Whether to enable the Policy Controller (Gatekeeper) addon."
  type        = bool
  default     = false # Corresponds to Azure 'enable_azure_policy'
}

# Azure Logging mapping
variable "enable_logging" {
  description = "Whether to enable Cloud Logging integration for the cluster."
  type        = bool
  default     = true # Often default for GKE
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring integration for the cluster."
  type        = bool
  default     = true # Often default for GKE
}

# Variables from Azure that don't have direct, common GKE variable equivalents:
# resource_group_name (implied by project)
# names (can use cluster_name and node_pool names)
# dns_prefix (Azure specific)
# node_resource_group (GCP manages this)
# identity_type (handled by service_account)
# user_assigned_identity (handled by service_account)
# user_assigned_identity_name (handled by service_account)
# outbound_type (handled by VPC/NAT configuration)
# configure_network_role (GCP IAM on SA/project)
# acr_pull_access (GCP IAM on SA/project for GCR/AR)
# log_analytics_workspace_id (handled by enabling logging/monitoring)
```