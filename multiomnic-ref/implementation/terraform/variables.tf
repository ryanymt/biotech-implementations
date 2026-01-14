# =============================================================================
# Cloud-Native Multiomics Platform - Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Optional Variables with Defaults
# -----------------------------------------------------------------------------

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources (Cloud Batch VMs)"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# -----------------------------------------------------------------------------
# Storage Configuration
# -----------------------------------------------------------------------------

variable "storage_location" {
  description = "Location for Cloud Storage buckets (region or multi-region)"
  type        = string
  default     = "US"
}

variable "bucket_retention_days" {
  description = "Number of days to retain results data before moving to cheaper storage"
  type        = number
  default     = 90
}

variable "staging_retention_days" {
  description = "Number of days to retain intermediate/staging data before deletion. Set to 7 for POC to prevent storage creep."
  type        = number
  default     = 7  # Aggressive cleanup for POC - prevents 50% of long-term storage costs
}

# -----------------------------------------------------------------------------
# Compute Configuration
# -----------------------------------------------------------------------------

variable "use_spot_vms" {
  description = "Whether to use Spot VMs for Cloud Batch jobs (cost savings up to 90%)"
  type        = bool
  default     = true
}

variable "max_batch_vcpus" {
  description = "Maximum vCPUs allowed for Cloud Batch jobs"
  type        = number
  default     = 1000
}

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

variable "create_vpc" {
  description = "Whether to create a new VPC or use an existing one"
  type        = bool
  default     = true
}

variable "existing_vpc_name" {
  description = "Name of existing VPC to use (if create_vpc is false)"
  type        = string
  default     = ""
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for private subnets"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# BigQuery Configuration
# -----------------------------------------------------------------------------

variable "bigquery_dataset_id" {
  description = "ID for the BigQuery dataset storing genomic variants"
  type        = string
  default     = "genomics_warehouse"
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

# -----------------------------------------------------------------------------
# Public Data Sources (Read-Only)
# -----------------------------------------------------------------------------

variable "public_data_sources" {
  description = "Public GCS buckets for genomic data (1000 Genomes, Platinum Genomes)"
  type        = map(string)
  default = {
    "1000_genomes"     = "gs://genomics-public-data/1000-genomes/"
    "platinum_genomes" = "gs://genomics-public-data/platinum-genomes/"
    "clinvar"          = "gs://genomics-public-data/clinvar/"
  }
}
