# =============================================================================
# Cloud-Native Multiomics Platform - IAM Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Service Account: Batch Runner
# -----------------------------------------------------------------------------
# Used by Cloud Batch VMs to execute genomic analysis tasks

resource "google_service_account" "batch_runner" {
  account_id   = "batch-runner"
  display_name = "Cloud Batch Pipeline Runner"
  description  = "Service account for Cloud Batch VMs running genomic analysis"
}

# Batch runner needs compute instance permissions
resource "google_project_iam_member" "batch_runner_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.batch_runner.email}"
}

# Batch runner needs to access Cloud Storage
resource "google_project_iam_member" "batch_runner_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.batch_runner.email}"
}

# Batch runner needs logging capabilities
resource "google_project_iam_member" "batch_runner_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.batch_runner.email}"
}

# -----------------------------------------------------------------------------
# Service Account: Pipeline Runner
# -----------------------------------------------------------------------------
# Used by Nextflow/Cromwell orchestrators to manage pipelines

resource "google_service_account" "pipeline_runner" {
  account_id   = "pipeline-runner"
  display_name = "Nextflow Pipeline Orchestrator"
  description  = "Service account for Nextflow/Cromwell to orchestrate Cloud Batch jobs"
}

# Pipeline runner needs to submit Cloud Batch jobs
resource "google_project_iam_member" "pipeline_runner_batch" {
  project = var.project_id
  role    = "roles/batch.jobsEditor"
  member  = "serviceAccount:${google_service_account.pipeline_runner.email}"
}

# Pipeline runner can act as the batch runner SA
resource "google_service_account_iam_member" "pipeline_can_use_batch" {
  service_account_id = google_service_account.batch_runner.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.pipeline_runner.email}"
}

# Pipeline runner needs compute permissions to launch VMs
resource "google_project_iam_member" "pipeline_runner_compute" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.pipeline_runner.email}"
}

# -----------------------------------------------------------------------------
# Service Account: BigQuery Analyst
# -----------------------------------------------------------------------------
# Used for tertiary analysis and data warehouse access

resource "google_service_account" "bq_analyst" {
  account_id   = "bq-analyst"
  display_name = "BigQuery Data Analyst"
  description  = "Service account for BigQuery access and Variant Transforms jobs"
}

# BigQuery analyst can query data
resource "google_project_iam_member" "bq_analyst_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.bq_analyst.email}"
}

# BigQuery analyst can read/write to genomics dataset
resource "google_bigquery_dataset_iam_member" "bq_analyst_editor" {
  dataset_id = google_bigquery_dataset.genomics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.bq_analyst.email}"
}

# BigQuery analyst can run Dataflow jobs (for Variant Transforms)
resource "google_project_iam_member" "bq_analyst_dataflow" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.bq_analyst.email}"
}

# -----------------------------------------------------------------------------
# Service Account: Vertex AI Runner
# -----------------------------------------------------------------------------
# Used for AI/ML pipelines (AlphaFold, DeepVariant)

resource "google_service_account" "vertex_runner" {
  account_id   = "vertex-runner"
  display_name = "Vertex AI Pipeline Runner"
  description  = "Service account for Vertex AI pipelines and ML workloads"
}

# Vertex runner needs AI Platform permissions
resource "google_project_iam_member" "vertex_runner_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.vertex_runner.email}"
}

# Vertex runner needs to access BigQuery for training data
resource "google_project_iam_member" "vertex_runner_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.vertex_runner.email}"
}

# Vertex runner needs storage access
resource "google_project_iam_member" "vertex_runner_storage" {
  project = var.project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${google_service_account.vertex_runner.email}"
}
