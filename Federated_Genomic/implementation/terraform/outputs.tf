# =============================================================================
# Cloud-Native Multiomics Platform - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Storage Outputs
# -----------------------------------------------------------------------------

output "results_bucket_name" {
  description = "Name of the Cloud Storage bucket for pipeline results"
  value       = google_storage_bucket.results.name
}

output "results_bucket_url" {
  description = "GCS URL for the results bucket"
  value       = google_storage_bucket.results.url
}

output "staging_bucket_name" {
  description = "Name of the Cloud Storage bucket for intermediate data"
  value       = google_storage_bucket.staging.name
}

# -----------------------------------------------------------------------------
# Networking Outputs
# -----------------------------------------------------------------------------

output "vpc_name" {
  description = "Name of the VPC network"
  value       = var.create_vpc ? google_compute_network.main[0].name : var.existing_vpc_name
}

output "subnet_name" {
  description = "Name of the compute subnet"
  value       = var.create_vpc ? google_compute_subnetwork.compute[0].name : null
}

output "subnet_self_link" {
  description = "Self-link of the compute subnet for Cloud Batch"
  value       = var.create_vpc ? google_compute_subnetwork.compute[0].self_link : null
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "batch_service_account_email" {
  description = "Email of the Cloud Batch service account"
  value       = google_service_account.batch_runner.email
}

output "pipeline_service_account_email" {
  description = "Email of the pipeline orchestration service account"
  value       = google_service_account.pipeline_runner.email
}

# -----------------------------------------------------------------------------
# BigQuery Outputs
# -----------------------------------------------------------------------------

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for genomic data"
  value       = google_bigquery_dataset.genomics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.genomics.location
}

# -----------------------------------------------------------------------------
# Connection Strings & Configuration
# -----------------------------------------------------------------------------

output "nextflow_config_snippet" {
  description = "Configuration snippet for Nextflow to use this infrastructure"
  value       = <<-EOT
    // Add to nextflow.config:
    process {
      executor = 'google-batch'
      container = 'YOUR_CONTAINER_IMAGE'
    }
    
    google {
      project = '${var.project_id}'
      region  = '${var.region}'
      batch {
        spot = ${var.use_spot_vms}
        network = '${var.create_vpc ? google_compute_network.main[0].self_link : ""}'
        subnetwork = '${var.create_vpc ? google_compute_subnetwork.compute[0].self_link : ""}'
        serviceAccountEmail = '${google_service_account.batch_runner.email}'
      }
    }
    
    workDir = '${google_storage_bucket.staging.url}/work'
  EOT
}

output "project_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    project_id   = var.project_id
    region       = var.region
    environment  = var.environment
    results_url  = google_storage_bucket.results.url
    staging_url  = google_storage_bucket.staging.url
    bigquery     = "${var.project_id}.${google_bigquery_dataset.genomics.dataset_id}"
  }
}
