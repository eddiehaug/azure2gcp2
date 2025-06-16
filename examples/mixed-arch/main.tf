terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0" # Use a modern version
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.1.2"
    }
  }
  required_version = "~> 1.0"
}

provider "google" {
  # Configure project and region/zone here or via environment variables
  # project = "your-gcp-project-id"
  # region  = "your-gcp-region"
}

data "google_client_config" "current" {}

data "google_container_cluster_auth" "gke" {
  name     = google_container_cluster.gke_cluster.name
  location = google_container_cluster.gke_cluster.location
}

provider "kubernetes" {
  host                   = google_container_cluster.gke_cluster.endpoint
  cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth.0.cluster_ca_certificate)
  token                  = data.google_container_cluster_auth.gke.token
}

provider "helm" {
  kubernetes {
    host                   = google_container_cluster.gke_cluster.endpoint
    cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth.0.cluster_ca_certificate)
    token                  = data.google_container_cluster_auth.gke.token
  }
}


data "http" "my_ip" {
  url = "http://ipv4.icanhazip.com"
}

resource "random_string" "random" {
  length  = 12
  upper   = false
  number  = false
  special = false
}

resource "random_password" "admin" {
  length      = 14
  special     = true
}

# GCP equivalent for Resource Group is the Project,
# and logical grouping is often done via VPC Network and Subnets
# We'll use variables/locals for project/region and naming

locals {
  project_id   = data.google_client_config.current.project
  region       = "us-central1" # Replace with your desired region
  cluster_name = "gke-${random_string.random.result}"
  network_name = "vpc-${random_string.random.result}"
}

# Virtual Network and Subnets
resource "google_compute_network" "vpc_network" {
  name                    = local.network_name
  auto_create_subnetworks = false # We define custom subnets
}

resource "google_compute_subnetwork" "private_subnet" {
  name          = "${local.network_name}-private"
  ip_cidr_range = "10.1.0.0/24"
  region        = local.region
  network       = google_compute_network.vpc_network.self_link
  # Private Google Access or Cloud NAT might be needed depending on cluster setup
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = "${local.network_name}-public"
  ip_cidr_range = "10.1.1.0/24"
  region        = local.region
  network       = google_compute_network.vpc_network.self_link
}

# GCP Firewall Rules (equivalent to Azure NSG Rules)
# Firewall rules are global but applied to instances based on network tags or service accounts.
# Targeting load balancer IP is not a typical GCP firewall pattern.
# A common pattern is to allow ingress to node pool instances via tags.
resource "google_compute_firewall" "allow_http_to_nodes" {
  name    = "allow-${local.cluster_name}-http"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  # Target the nodes by network tag. GKE often assigns tags based on cluster name or node pool name.
  # Check the GKE cluster outputs or resource attributes for the exact tag format.
  # A common tag format is 'gke-<cluster-name>-<random-string>-node'.
  # Or node pools have tags like 'gke-<cluster-name>-<nodepool-name>-<random-string>-node'.
  # Let's use the tags assigned to the node pools.
  # You'll need to retrieve the actual tags applied by GKE.
  # Assuming GKE applies tags like 'gke-cluster-node' and per-pool tags.
  # We will apply a custom tag to node pools for clearer targeting.
  target_tags = [
    "${local.cluster_name}-linuxweb",
    "${local.cluster_name}-winweb"
  ]
}


# Google Kubernetes Engine (GKE) Cluster
resource "google_container_cluster" "gke_cluster" {
  name                     = local.cluster_name
  location                 = local.region
  initial_node_count       = 1 # Minimal initial count, node pools will manage nodes
  remove_default_node_pool = true # Remove the default node pool created with the cluster
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name # Default subnet for cluster
  # Enable VPC-native networking (equivalent to Azure CNI)
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Master authorized networks - equivalent to AKS authorized IP ranges
  # master_authorized_networks_config {
  #   cidr_blocks {
  #     display_name = "my-ip"
  #     cidr_block   = "${chomp(data.http.my_ip.response_body)}/32"
  #   }
  # }

  # Workload Identity (Recommended over node service account)
  # workload_identity_config {
  #   workload_pool = "${local.project_id}.svc.id.goog"
  # }

  # Private cluster configuration (Optional, based on Azure "private" subnet usage)
  # private_cluster_config {
  #   enable_private_nodes    = true
  #   enable_private_endpoint = false # Set to true to access master from VPC
  #   master_ipv4_cidr_block  = "172.16.0.0/28" # Needs a non-overlapping range
  # }

  release_channel {
    channel = "REGULAR" # or RAPID, STABLE
  }

  # Add-ons (optional)
  # addons_config {
  #   kubernetes_dashboard { disabled = true }
  #   network_policy_config { disabled = true }
  # }

  # Node config template for node pools (common settings)
  node_config {}

  # Windows node pools require specific configuration
  # node_config {
  #   windows_node_config {
  #     enable_integrity_monitoring = true
  #   }
  # }

  # Other configurations like logging, monitoring, networking etc.
  # logging_service = "logging.googleapis.com/kubernetes"
  # monitoring_service = "monitoring.googleapis.com/kubernetes"
  # networking_mode = "VPC_NATIVE"
}

# GKE Node Pools
# Azure 'system' node pool -> GKE 'system' or management pool
resource "google_container_node_pool" "system_nodes" {
  name       = "${local.cluster_name}-system"
  location   = local.region
  cluster    = google_container_cluster.gke_cluster.name
  node_count = 2 # Fixed count

  node_config {
    # Equivalent to Standard_B2s (2 vCPU, 4GB RAM) - closest GCP is e2-medium or n2d-medium
    machine_type = "e2-medium"
    disk_size_gb = 100 # Default is 100GB
    # Tags for firewall rules
    tags = ["${local.cluster_name}-system"]

    # Service Account for nodes (default is project default service account)
    # service_account = google_service_account.gke_node.email

    # Optional: Windows node config placeholder if needed for system pool
    # windows_node_config {}
  }

  # Put system nodes in the private subnet
  network_config {
    create_pod_range = false # Pods use the cluster secondary range
    subnetwork       = google_compute_subnetwork.private_subnet.self_link
  }

  # Auto-repair and auto-upgrade are enabled by default
}

# Azure 'linuxweb' node pool -> GKE Linux node pool
resource "google_container_node_pool" "linuxweb_nodes" {
  name       = "${local.cluster_name}-linuxweb"
  location   = local.region
  cluster    = google_container_cluster.gke_cluster.name
  # initial_node_count not needed with autoscaling

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    # Equivalent to Standard_B2ms (2 vCPU, 8GB RAM) - closest GCP is e2-medium or n2d-medium
    machine_type = "e2-medium"
    disk_size_gb = 100 # Default is 100GB
    # OS Image Type (default is COS_CONTAINERD, which is Linux)
    # image_type = "COS_CONTAINERD"
    # Tags for firewall rules
    tags = ["${local.cluster_name}-linuxweb"]

    # Service Account for nodes (default is project default service account)
    # service_account = google_service_account.gke_node.email
  }

  # Put linuxweb nodes in the public subnet
  network_config {
    create_pod_range = false # Pods use the cluster secondary range
    subnetwork       = google_compute_subnetwork.public_subnet.self_link
  }
}

# Azure 'winweb' node pool -> GKE Windows Server node pool
resource "google_container_node_pool" "winweb_nodes" {
  name       = "${local.cluster_name}-winweb"
  location   = local.region
  cluster    = google_container_cluster.gke_cluster.name
  # initial_node_count not needed with autoscaling

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    # Equivalent to Standard_D4a_v4 (4 vCPU, 16GB RAM) - GCP equivalent n2d-standard-4 or e2-standard-4
    machine_type = "n2d-standard-4" # Or e2-standard-4
    disk_size_gb = 100 # Default is 100GB

    # Configure as Windows node pool
    image_type = "WINDOWS_LTSC_CONTAINERD" # or WINDOWS_SAC_CONTAINERD
    # Tags for firewall rules
    tags = ["${local.cluster_name}-winweb"]

    # Service Account for nodes (default is project default service account)
    # service_account = google_service_account.gke_node.email

    # Windows specific configurations might be added here if needed, e.g., for specific OS features
    windows_node_config {
      enable_integrity_monitoring = true
    }
  }

  # Put winweb nodes in the public subnet
  network_config {
    create_pod_range = false # Pods use the cluster secondary range
    subnetwork       = google_compute_subnetwork.public_subnet.self_link
  }
}


# Helm releases remain the same, but node selectors need to match GKE node pool labels
# GKE node pools automatically get labels like cloud.google.com/gke-nodepool: <nodepool-name>
resource "helm_release" "nginx" {
  depends_on = [google_container_cluster.gke_cluster, google_container_node_pool.linuxweb_nodes] # Depend on cluster and specific node pool
  name       = "nginx"
  chart      = "./helm_chart" # Assuming chart path is correct

  set {
    name  = "name"
    value = "nginx"
  }

  set {
    name  = "image"
    value = "nginx:latest"
  }

  # Update nodeSelector to match GKE label for linuxweb node pool
  set {
    name  = "nodeSelector"
    value = yamlencode({ "cloud.google.com/gke-nodepool" = google_container_node_pool.linuxweb_nodes.name })
  }
}

resource "helm_release" "iis" {
  depends_on = [google_container_cluster.gke_cluster, google_container_node_pool.winweb_nodes] # Depend on cluster and specific node pool
  name       = "iis"
  chart      = "./helm_chart" # Assuming chart path is correct
  timeout    = 600

  set {
    name  = "name"
    value = "iis"
  }

  set {
    name  = "image"
    value = "mcr.microsoft.com/iis/iis-for-windows:latest" # Use official Microsoft image
  }

  # Update nodeSelector to match GKE label for winweb node pool
  set {
    name  = "nodeSelector"
    value = yamlencode({ "cloud.google.com/gke-nodepool" = google_container_node_pool.winweb_nodes.name })
  }
}

# Data sources for Kubernetes services remain the same
data "kubernetes_service" "nginx" {
  depends_on = [helm_release.nginx]
  metadata {
    name = "nginx"
    # Add namespace if not default
    # namespace = "default"
  }
}

data "kubernetes_service" "iis" {
  depends_on = [helm_release.iis]
  metadata {
    name = "iis"
    # Add namespace if not default
    # namespace = "default"
  }
}

# Outputs
output "nginx_url" {
  description = "The IP address of the Nginx LoadBalancer service."
  # Accessing the LoadBalancer IP is the same
  value = "http://${data.kubernetes_service.nginx.status.0.load_balancer.0.ingress.0.ip}"
}

output "iis_url" {
  description = "The IP address of the IIS LoadBalancer service."
  # Accessing the LoadBalancer IP is the same
  value = "http://${data.kubernetes_service.iis.status.0.load_balancer.0.ingress.0.ip}"
}

output "gke_login_command" {
  description = "Command to configure kubectl access to the GKE cluster."
  # Provide the gcloud command to get credentials
  value = "gcloud container clusters get-credentials ${google_container_cluster.gke_cluster.name} --zone ${google_container_cluster.gke_cluster.location} --project ${local.project_id}"
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.gke_cluster.name
}