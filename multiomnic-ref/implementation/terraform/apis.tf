# =============================================================================
# Cloud-Native Multiomics Platform - API Enablement
# =============================================================================

# -----------------------------------------------------------------------------
# Core Compute APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "batch" {
  service            = "batch.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project_service.compute]
}

# Note: Life Sciences API is being deprecated in favor of Cloud Batch
# Keeping for backward compatibility with older pipelines
resource "google_project_service" "lifesciences" {
  service            = "lifesciences.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project_service.compute]
}

# -----------------------------------------------------------------------------
# Storage & Data APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "bigquery" {
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataflow" {
  service            = "dataflow.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project_service.compute]
}

# -----------------------------------------------------------------------------
# Container & Artifact APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "containerregistry" {
  service            = "containerregistry.googleapis.com"
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# AI/ML APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "aiplatform" {
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project_service.compute]
}

resource "google_project_service" "notebooks" {
  service            = "notebooks.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project_service.compute]
}

# -----------------------------------------------------------------------------
# Networking & Security APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials" {
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Monitoring & Logging APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# BigQuery Dataset (placed here for API dependency)
# -----------------------------------------------------------------------------

resource "google_bigquery_dataset" "genomics" {
  dataset_id                 = var.bigquery_dataset_id
  location                   = var.bigquery_location
  delete_contents_on_destroy = var.environment != "prod"

  labels = local.common_labels

  depends_on = [google_project_service.bigquery]
}
