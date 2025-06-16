output "id" {
  description = "Google Kubernetes Engine cluster ID"
  value       = google_container_cluster.primary.id
}

output "name" {
  description = "Google Kubernetes Engine cluster name"
  value       = google_container_cluster.primary.name
}

output "endpoint" {
  description = "Google Kubernetes Engine cluster endpoint"
  value       = google_container_cluster.primary.endpoint
}

output "project_id" {
  description = "The project ID of the cluster"
  value       = google_container_cluster.primary.project
}

output "location" {
  description = "The location (region or zone) of the cluster"
  value       = google_container_cluster.primary.location
}

# Note: effective_outbound_ips_ids is not directly applicable to GKE in the same way.
# Outbound connectivity depends on VPC networking, Cloud NAT, etc., which are separate resources.

# Note: kube_config and kube_config_raw outputs are not standard for GKE.
# Users typically authenticate using gcloud and Google Identity/IAM roles.
# The parameters needed to *construct* a kubeconfig are available, but the full config is not output directly.

output "host" {
  description = "Google Kubernetes Engine cluster endpoint"
  value       = google_container_cluster.primary.endpoint
}

# Note: username, password, client_certificate, client_key are for basic auth,
# which is not the standard or recommended authentication method for GKE.
# Authentication is typically handled via Google Identity and IAM roles.

output "cluster_ca_certificate" {
  description = "Google Kubernetes Engine cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
}

output "node_pool_service_account" {
  description = "Service account used by the default node pool (or first defined node pool)"
  # Assuming a default node pool or a node pool resource named 'primary_node_pool' exists and is referenced
  # If using a default node pool defined within the cluster resource itself:
  # value = google_container_cluster.primary.node_config[0].service_account
  # If using a separate node pool resource (common practice):
  value = google_container_node_pool.primary_node_pool.node_config[0].service_account
}

# Note: kubelet_identity corresponds to the identity used by nodes (kubelets).
# In GKE, this is the service account assigned to the nodes in the node pool.
output "kubelet_identity_service_account" {
  description = "Service account used by the nodes (kubelets) in the default node pool (or first defined node pool)"
  # Assuming a default node pool or a node pool resource named 'primary_node_pool' exists and is referenced
  # If using a default node pool defined within the cluster resource itself:
  # value = google_container_cluster.primary.node_config[0].service_account
  # If using a separate node pool resource (common practice):
  value = google_container_node_pool.primary_node_pool.node_config[0].service_account
}