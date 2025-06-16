provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "google_service_account" "gke_node" {
  count = (var.create_node_service_account && var.existing_node_service_account_email == null ? 1 : 0)

  project      = var.project_id
  account_id   = "gke-node-sa-${random_id.suffix.hex}"
  display_name = "Service Account for GKE Nodes"
}

locals {
  node_service_account_email = (var.create_node_service_account && var.existing_node_service_account_email == null ?
    google_service_account.gke_node[0].email :
    (var.existing_node_service_account_email != null ?
      var.existing_node_service_account_email :
      "default"))

  default_node_pool_config_gcp = {
     machine_type         = var.default_node_pool_config.vm_size
     disk_size_gb         = var.default_node_pool_config.os_disk_size_gb
     disk_type            = var.default_node_pool_config.os_disk_type
     node_locations       = var.default_node_pool_config.availability_zones
     enable_auto_scaling  = var.default_node_pool_config.enable_auto_scaling
     node_count           = var.default_node_pool_config.node_count
     min_count            = var.default_node_pool_config.min_count
     max_count            = var.default_node_pool_config.max_count
     enable_public_ip     = var.default_node_pool_config.enable_node_public_ip
     max_pods_per_node    = var.default_node_pool_config.max_pods
     node_labels          = var.default_node_pool_config.node_labels
     resource_labels      = var.default_node_pool_config.tags
     max_surge            = var.default_node_pool_config.max_surge
     image_type           = var.default_node_pool_config.os_type
     node_taints_list     = [
                               for taint_k, taint_v in lookup(var.default_node_pool_config, "node_taints", {}) : {
                                 key    = taint_k
                                 value  = taint_v
                                 effect = "NO_SCHEDULE"
                               }
                             ]
     scheduling_spot      = lookup(var.default_node_pool_config, "priority", "Regular") == "Spot"
     shielded_instance_config_enabled = lookup(var.default_node_pool_config, "enable_host_encryption", false)
     max_unavailable    = lookup(var.default_node_pool_config, "max_unavailable", 1)
  }

  additional_node_pools_gcp_config = {
     for name, config in var.additional_node_pools : name => {
       machine_type         = config.vm_size
       disk_size_gb         = config.os_disk_size_gb
       disk_type            = config.os_disk_type
       node_locations       = config.availability_zones
       enable_auto_scaling  = config.enable_auto_scaling
       node_count           = config.node_count
       min_count            = config.min_count
       max_count            = config.max_count
       enable_public_ip     = config.enable_node_public_ip
       max_pods_per_node    = config.max_pods
       node_labels          = config.node_labels
       resource_labels      = config.tags
       max_surge            = config.max_surge
       image_type           = config.os_type
       node_taints_list     = [
                                for taint_k, taint_v in lookup(config, "node_taints", {}) : {
                                  key    = taint_k
                                  value  = taint_v
                                  effect = "NO_SCHEDULE"
                                }
                              ]
       scheduling_spot      = lookup(config, "priority", "Regular") == "Spot"
       shielded_instance_config_enabled = lookup(config, "enable_host_encryption", false)
       max_unavailable    = lookup(config, "max_unavailable", 1)
     }
   }
}

resource "google_project_iam_member" "gke_control_plane_network_user" {
  project = var.project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:service-${data.google_project.current.number}@container.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "gke_node_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.node_service_account_email}"
}

resource "google_project_iam_member" "gke_node_monitoring_writer" {
    project = var.project_id
    role    = "roles/monitoring.metricWriter"
    member  = "serviceAccount:${local.node_service_account_email}"
}

resource "google_project_iam_member" "gke_node_logging_writer" {
    project = var.project_id
    role    = "roles/logging.logWriter"
    member  = "serviceAccount:${local.node_service_account_email}"
}

resource "google_container_cluster" "gke" {
  name     = var.name
  project  = var.project_id
  location = var.region
  labels   = var.tags

  description        = var.description
  initial_node_count = null
  remove_default_node_pool = true

  dynamic "release_channel" {
    for_each = var.release_channel != null ? [1] : []
    content {
      channel = var.release_channel
    }
  }

  dynamic "min_master_version" {
     for_each = var.release_channel == null && var.kubernetes_version != null ? [1] : []
     content {
       min_master_version = var.kubernetes_version
     }
  }


  dynamic "private_cluster_config" {
    for_each = var.private_cluster_enabled ? [1] : []
    content {
      enable_private_endpoint = var.private_cluster_enabled
      enable_private_nodes    = var.private_cluster_enabled
    }
  }

  network_config {
    network    = var.vpc_network_name
    subnetwork = var.vpc_subnet_name
    use_ip_aliases = true

    ip_allocation_policy {
      cluster_secondary_range_name = var.pod_secondary_range_name
      services_secondary_range_name = var.service_secondary_range_name
    }

    network_policy_config {
      enabled = var.network_policy
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = var.api_server_authorized_ip_ranges
    content {
      cidr_blocks {
        cidr_block   = master_authorized_networks_config.value
        display_name = "Authorized Range ${master_authorized_networks_config.key}"
      }
    }
  }

  addons_config {
    http_load_balancing { enabled = true }
    horizontal_pod_autoscaling { enabled = true }
    network_policy_config { enabled = var.network_policy }
  }

  logging_service   = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  dynamic "authenticator_groups_config" {
     for_each = var.enable_google_groups_rbac && var.rbac_admin_google_group != null ? [1] : []
     content {
        security_group = var.rbac_admin_google_group
     }
  }

  depends_on = [
    google_project_iam_member.gke_control_plane_network_user,
  ]
}

resource "google_container_cluster_rbac_policy" "gke_admin_group_policy" {
  count = (var.enable_google_groups_rbac && var.rbac_admin_google_group != null ? 1 : 0)

  cluster           = google_container_cluster.gke.name
  project           = var.project_id
  location          = var.region
  policy {
    group = var.rbac_admin_google_group
    role  = "rbac/cluster-admin"
  }
}

resource "google_container_node_pool" "default" {
  cluster    = google_container_cluster.gke.name
  project    = var.project_id
  location   = var.region

  name       = var.default_node_pool_name

  node_config {
    machine_type = local.default_node_pool_config_gcp.machine_type
    disk_size_gb = local.default_node_pool_config_gcp.disk_size_gb
    disk_type    = local.default_node_pool_config_gcp.disk_type

    service_account = local.node_service_account_email

    labels        = local.default_node_pool_config_gcp.node_labels
    resource_labels = local.default_node_pool_config_gcp.resource_labels

    node_locations = local.default_node_pool_config_gcp.node_locations

    shielded_instance_config {
        enable_integrity_monitoring = lookup(local.default_node_pool_config_gcp, "shielded_instance_config_enabled", false)
        enable_secure_boot          = lookup(local.default_node_pool_config_gcp, "shielded_instance_config_enabled", false)
    }

    no_provisioned_ip = !local.default_node_pool_config_gcp.enable_public_ip

    max_pods_per_node = local.default_node_pool_config_gcp.max_pods_per_node

    image_type = local.default_node_pool_config_gcp.image_type

    node_network_config {
        create_pod_range = false
        pod_ipv4_cidr_block = ""
        pod_range = var.pod_secondary_range_name
    }

    taints = local.default_node_pool_config_gcp.node_taints_list

    scheduling {
        automatic_repair = true
        automatic_upgrade = true
        spot = local.default_node_pool_config_gcp.scheduling_spot
    }
  }

  autoscaling {
    enabled        = local.default_node_pool_config_gcp.enable_auto_scaling
    min_node_count = local.default_node_pool_config_gcp.min_count
    max_node_count = local.default_node_pool_config_gcp.max_count
  }

  node_count = (local.default_node_pool_config_gcp.enable_auto_scaling ? null : local.default_node_pool_config_gcp.node_count)

  upgrade_settings {
    max_surge       = local.default_node_pool_config_gcp.max_surge
    max_unavailable = local.default_node_pool_config_gcp.max_unavailable
  }

  depends_on = [google_container_cluster.gke]
}

resource "google_container_node_pool" "additional" {
  for_each = local.additional_node_pools_gcp_config

  cluster    = google_container_cluster.gke.name
  project    = var.project_id
  location   = var.region

  name       = each.key

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type

    service_account = local.node_service_account_email

    labels        = each.value.node_labels
    resource_labels = each.value.resource_labels

    node_locations = each.value.node_locations

    shielded_instance_config {
        enable_integrity_monitoring = lookup(each.value, "shielded_instance_config_enabled", false)
        enable_secure_boot          = lookup(each.value, "shielded_instance_config_enabled", false)
    }

    no_provisioned_ip = !each.value.enable_public_ip

    max_pods_per_node = each.value.max_pods_per_node

    image_type = each.value.image_type

    node_network_config {
        create_pod_range = false
        pod_ipv4_cidr_block = ""
        pod_range = var.pod_secondary_range_name
    }

    taints = each.value.node_taints_list

    scheduling {
        automatic_repair = true
        automatic_upgrade = true
        spot = each.value.scheduling_spot
    }
  }

  autoscaling {
    enabled        = each.value.enable_auto_scaling
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  node_count = (each.value.enable_auto_scaling ? null : each.value.node_count)

  upgrade_settings {
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  depends_on = [google_container_cluster.gke]
}

variable "project_id" {
  description = "The GCP project ID where the cluster will be created."
  type        = string
}

variable "region" {
  description = "The GCP region for the cluster (e.g., us-central1)."
  type        = string
}

variable "name" {
  description = "The name of the GKE cluster."
  type        = string
}

variable "description" {
  description = "The description for the GKE cluster."
  type        = string
  default     = "Managed by Terraform"
}

variable "tags" {
  description = "A map of tags to assign to the cluster (becomes GCP labels)."
  type        = map(string)
  default     = {}
}

variable "release_channel" {
  description = "The GKE release channel (e.g., REGULAR, STABLE, RAPID). Set to null to use a specific version."
  type        = string
  default     = "REGULAR"
}

variable "kubernetes_version" {
   description = "The specific Kubernetes version to use. Set to null if using a release_channel."
   type        = string
   default     = null
}

variable "private_cluster_enabled" {
  description = "Whether to enable a private cluster."
  type        = bool
  default     = false
}

variable "vpc_network_name" {
  description = "The name of the VPC network the cluster will use."
  type        = string
}

variable "vpc_subnet_name" {
  description = "The name of the subnet within the VPC the cluster will use."
  type        = string
}

variable "pod_secondary_range_name" {
   description = "The name of the secondary range used for pods in the cluster subnet (for VPC-native)."
   type        = string
}

 variable "service_secondary_range_name" {
    description = "The name of the secondary range used for services in the cluster subnet (for VPC-native)."
    type        = string
 }

variable "network_policy" {
  description = "Whether to enable Kubernetes Network Policy enforcement."
  type        = bool
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  description = "List of CIDR blocks to authorize for access to the master (API server) endpoint."
  type        = list(string)
  default     = []
}

variable "create_node_service_account" {
   description = "Whether to create a new service account for the GKE nodes."
   type        = bool
   default     = true
}

variable "existing_node_service_account_email" {
   description = "Email of an existing service account to use for the GKE nodes (if not creating a new one)."
   type        = string
   default     = null
}

variable "enable_google_groups_rbac" {
  description = "Whether to enable Google Groups for Kubernetes RBAC integration via GKE Identity Service."
  type        = bool
  default     = false
}

variable "rbac_admin_google_group" {
  description = "The Google Group email address to bind to the cluster-admin ClusterRole via GKE RBAC policy."
  type        = string
  default     = null
}

variable "default_node_pool_name" {
  description = "The name to give the default node pool."
  type        = string
  default     = "default-pool"
}

variable "default_node_pool_config" {
  description = "Configuration for the default node pool."
  type = object({
    vm_size            = string
    os_disk_size_gb    = number
    os_disk_type       = string
    availability_zones = list(string)
    enable_auto_scaling= bool
    node_count         = number
    min_count          = number
    max_count          = number
    enable_host_encryption = bool
    enable_node_public_ip  = bool
    max_pods           = number
    node_labels        = map(string)
    tags               = map(string)
    max_surge          = number
    os_type            = string
    node_taints        = optional(map(string), {})
    priority           = optional(string, "Regular")
    max_unavailable    = optional(number, 1)
  })
}

variable "additional_node_pools" {
  description = "Map of configurations for additional node pools."
  type = map(object({
    vm_size            = string
    os_disk_size_gb    = number
    os_disk_type       = string
    availability_zones = list(string)
    enable_auto_scaling= bool
    node_count         = number
    min_count          = number
    max_count          = number
    enable_host_encryption = bool
    enable_node_public_ip  = bool
    max_pods           = number
    node_labels        = map(string)
    tags               = map(string)
    max_surge          = number
    os_type            = string
    node_taints        = optional(map(string), {})
    priority           = optional(string, "Regular")
    max_unavailable    = optional(number, 1)
  }))
  default = {}
}