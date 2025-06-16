locals {
  # Derive cluster name - similar pattern to Azure
  cluster_name = (var.cluster_name != null ? var.cluster_name :
  "${var.names.product_name}-${var.names.environment}-${var.names.location}") # Adjusting naming convention slightly

  # Process node pool configurations - similar pattern to Azure
  node_pools            = zipmap(keys(var.node_pools), [for node_pool in values(var.node_pools) : merge(var.node_pool_defaults, node_pool)])
  additional_node_pools = { for k, v in local.node_pools : k => v if k != var.default_node_pool }

  # Check if any Windows node pools are present - applicable to GKE
  windows_nodes = (length([for v in values(local.node_pools) : v if lower(v.os_type) == "windows"]) > 0 ? true : false)

  # Format authorized IP ranges for API server - applicable to GKE
  # Assuming input variable structure is similar (map or list)
  authorized_networks = (var.api_server_authorized_ip_ranges == null ? null : values(var.api_server_authorized_ip_ranges))

  # GCP equivalent for node resource group concept is not applicable in this way.
  # GCP equivalent for user assigned identity is service accounts, handled differently.
  # GCP equivalent for dns_prefix as AKS API FQDN isn't a direct mapping.
  # GCP identity handling is via service accounts, not Azure AD principals.

  # Azure-specific validations are removed as they don't apply to GKE.
  # Any GKE-specific validations would need to be added here or in pre/postconditions.
}