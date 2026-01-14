# =============================================================================
# Cloud-Native Multiomics Platform - Cloud Storage Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Pipeline Results Bucket
# -----------------------------------------------------------------------------
# Stores final pipeline outputs (VCF files, QC reports, analysis results)

resource "google_storage_bucket" "results" {
  name          = "${local.bucket_prefix}-results-${var.environment}"
  location      = var.storage_location
  force_destroy = var.environment != "prod" # Prevent accidental deletion in prod
  
  uniform_bucket_level_access = true

  # Security: Prevent public access (HIPAA/GDPR compliance)
  public_access_prevention = "enforced"

  versioning {
    enabled = var.environment == "prod"
  }

  # Move old results to cheaper storage after 90 days
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Archive to coldline after 1 year
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Abort incomplete multipart uploads after 7 days
  lifecycle_rule {
    condition {
      age = 7
      with_state = "ANY"
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# Pipeline Staging Bucket
# -----------------------------------------------------------------------------
# Stores intermediate data and Nextflow work directories

resource "google_storage_bucket" "staging" {
  name          = "${local.bucket_prefix}-staging-${var.environment}"
  location      = var.storage_location
  force_destroy = true # Intermediate data can always be regenerated
  
  uniform_bucket_level_access = true

  # Security: Prevent public access (HIPAA/GDPR compliance)
  public_access_prevention = "enforced"

  # AGGRESSIVE CLEANUP: Delete intermediate files after 7 days for POC
  # This prevents "storage creep" which can be 50% of long-term costs
  lifecycle_rule {
    condition {
      age = var.staging_retention_days  # Default: 7 days for POC
    }
    action {
      type = "Delete"
    }
  }

  # Abort incomplete multipart uploads after 1 day
  lifecycle_rule {
    condition {
      age = 1
      with_state = "ANY"
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# Reference Data Bucket (Optional)
# -----------------------------------------------------------------------------
# Stores reference genomes and annotation databases

resource "google_storage_bucket" "reference" {
  name          = "${local.bucket_prefix}-reference-${var.environment}"
  location      = var.storage_location
  force_destroy = false # Reference data should never be accidentally deleted
  
  uniform_bucket_level_access = true

  # Security: Prevent public access (HIPAA/GDPR compliance)
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# Bucket IAM Bindings
# -----------------------------------------------------------------------------

# Batch service account can read/write staging
resource "google_storage_bucket_iam_member" "batch_staging_writer" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.batch_runner.email}"
}

# Batch service account can write results
resource "google_storage_bucket_iam_member" "batch_results_writer" {
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.batch_runner.email}"
}

# Batch service account can read reference
resource "google_storage_bucket_iam_member" "batch_reference_reader" {
  bucket = google_storage_bucket.reference.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.batch_runner.email}"
}

# Pipeline runner can manage all buckets
resource "google_storage_bucket_iam_member" "pipeline_staging_admin" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.pipeline_runner.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_results_admin" {
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.pipeline_runner.email}"
}
