terraform {
  required_version = ">= 0.14.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0" # Use a suitable version for the GCP provider
    }
    # The http provider is generic and not GCP specific.
    # Remove it unless it's used by other resources outside this snippet.
    # http = {
    #   source  = "hashicorp/http"
    #   version = ">= 1.2.0"
    # }
  }
}