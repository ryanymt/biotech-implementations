# =============================================================================
# Cloud-Native Multiomics Platform - Main Terraform Configuration
# =============================================================================
# Purpose: Orchestrates all infrastructure modules for the genomics platform
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0.0"
    }
  }

  # TODO: Configure remote backend for production
  # backend "gcs" {
  #   bucket  = "multiomics-terraform-state"
  #   prefix  = "terraform/state"
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  common_labels = {
    project     = "multiomics-platform"
    environment = var.environment
    managed_by  = "terraform"
  }

  # Bucket naming convention
  bucket_prefix = "${var.project_id}-multiomics"
}

# -----------------------------------------------------------------------------
# Module Composition
# -----------------------------------------------------------------------------

# Enable required Google Cloud APIs (defined in apis.tf)
# Note: API enablement is handled directly in apis.tf

# Storage resources (defined in storage.tf)
# Note: Buckets are defined directly in storage.tf

# Networking (defined in networking.tf)
# Note: VPC and subnets are defined directly in networking.tf

# IAM (defined in iam.tf)
# Note: Service accounts and bindings are defined directly in iam.tf

# -----------------------------------------------------------------------------
# Optional: Batch Queue Configuration
# -----------------------------------------------------------------------------

# resource "google_cloud_batch_job_template" "genomics_job" {
#   provider = google-beta
#   # TODO: Configure when Cloud Batch Terraform support is fully available
# }

# -----------------------------------------------------------------------------
# Outputs Reference
# -----------------------------------------------------------------------------
# All outputs are consolidated in outputs.tf
