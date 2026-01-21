# Multiomics Platform - Quick Start Guide

> **Time to Deploy:** ~30 minutes  
> **Prerequisites:** GCP project with billing enabled

---

## 🚀 Quick Deploy (Recommended)

```bash
# Clone the repository
git clone https://github.com/ryanymt/multiomnic-env.git
cd multiomnic-env/implementation

# Set your project
gcloud config set project YOUR_PROJECT_ID

# One-command deploy
./scripts/quick-deploy.sh 2>&1 | tee deploy.log
```

---

## 📋 Manual Step-by-Step Guide

### Phase 1: Prerequisites (5 min)

```bash
# 1. Authenticate
gcloud auth login
gcloud auth application-default login

# 2. Set project
export PROJECT_ID="YOUR_PROJECT_ID"
gcloud config set project $PROJECT_ID

# 3. Enable required APIs
gcloud services enable \
    compute.googleapis.com \
    batch.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    dataflow.googleapis.com
```

### Phase 2: Infrastructure (10 min)

```bash
cd implementation/terraform

# Initialize Terraform
terraform init

# Review changes
terraform plan \
    -var="project_id=$PROJECT_ID" \
    -var="environment=dev"

# Apply infrastructure
terraform apply \
    -var="project_id=$PROJECT_ID" \
    -var="environment=dev" \
    -auto-approve
```

**Resources Created:**
- VPC: `multiomics-vpc`
- GCS Buckets: `$PROJECT_ID-results-dev`, `$PROJECT_ID-staging-dev`, `$PROJECT_ID-reference-dev`
- BigQuery Dataset: `genomics_warehouse`
- IAM Roles for compute service account

### Phase 3: Build Variant Transforms Container (10 min)

```bash
# Create Artifact Registry repository
gcloud artifacts repositories create genomics-containers \
    --project=$PROJECT_ID \
    --location=us-central1 \
    --repository-format=docker

# Grant permissions
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
gcloud artifacts repositories add-iam-policy-binding genomics-containers \
    --project=$PROJECT_ID \
    --location=us-central1 \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/artifactregistry.admin"

# Clone and build Variant Transforms
git clone --depth 1 https://github.com/googlegenomics/gcp-variant-transforms.git
cd gcp-variant-transforms

# Create cloudbuild config for Artifact Registry
cat > cloudbuild_ar.yaml << 'EOF'
substitutions:
  _REGION: 'us-central1'
  _REPOSITORY: 'genomics-containers'
  _TAG: 'v1'
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '--tag=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/gcp-variant-transforms:${_TAG}'
      - '--tag=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/gcp-variant-transforms:latest'
      - '--file=docker/Dockerfile'
      - '.'
images:
  - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/gcp-variant-transforms:${_TAG}'
  - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPOSITORY}/gcp-variant-transforms:latest'
timeout: 3600s
EOF

# Build and push
gcloud builds submit --config=cloudbuild_ar.yaml --project=$PROJECT_ID .
cd ..
```

### Phase 4: Run DeepVariant Pipeline (2-3 hours)

```bash
cd implementation/scripts

# Submit parallel DeepVariant job
gcloud batch jobs submit deepvariant-parallel-$(date +%Y%m%d-%H%M%S) \
    --project=$PROJECT_ID \
    --location=us-central1 \
    --config=deepvariant-parallel-job.json

# Monitor job
gcloud batch jobs list --project=$PROJECT_ID --location=us-central1
```

### Phase 5: Merge VCF Shards (5 min)

```bash
# After DeepVariant completes, merge the shards
gcloud batch jobs submit merge-vcf-$(date +%Y%m%d-%H%M%S) \
    --project=$PROJECT_ID \
    --location=us-central1 \
    --config=merge-vcf-job.json
```

### Phase 6: Load VCF to BigQuery (30 min)

**Option A: Variant Transforms (full schema)**
```bash
# Update variant-transforms-job.json with your project ID
sed -i '' "s/multiomnic-ref/$PROJECT_ID/g" variant-transforms-job.json

gcloud batch jobs submit variant-transforms-$(date +%Y%m%d-%H%M%S) \
    --project=$PROJECT_ID \
    --location=us-central1 \
    --config=variant-transforms-job.json
```

**Option B: bcftools (simpler, for POC)**
```bash
gcloud batch jobs submit vcf-to-bq-$(date +%Y%m%d-%H%M%S) \
    --project=$PROJECT_ID \
    --location=us-central1 \
    --config=vcf-to-bigquery-job.json

# Then load TSV to BigQuery
bq load --source_format=CSV --field_delimiter=tab --skip_leading_rows=1 --replace \
  $PROJECT_ID:genomics_warehouse.deepvariant_variants \
  gs://$PROJECT_ID-results-dev/deepvariant-parallel/variants_for_bq.tsv \
  chromosome:STRING,position:INTEGER,id:STRING,ref:STRING,alt:STRING,quality:FLOAT,filter:STRING
```

### Phase 7: Create Looker Dashboard

See [LOOKER_STUDIO_GUIDE.md](LOOKER_STUDIO_GUIDE.md) for detailed instructions.

---

## 📁 Project Structure

```
implementation/
├── terraform/          # Infrastructure as Code
│   ├── main.tf         # Provider config
│   ├── apis.tf         # API enablement
│   ├── iam.tf          # IAM roles/permissions
│   ├── networking.tf   # VPC, firewall
│   ├── storage.tf      # GCS buckets
│   └── variables.tf    # Configuration variables
├── scripts/            # Automation scripts
│   ├── deploy.sh                      # Master deploy script
│   ├── deepvariant-parallel-job.json  # Parallel variant calling
│   ├── merge-vcf-job.json             # VCF merge job
│   ├── variant-transforms-job.json    # VCF to BigQuery (production)
│   └── vcf-to-bigquery-job.json       # VCF to BigQuery (POC)
├── pipelines/          # Nextflow pipelines
└── docs/               # Documentation
```

---

## ⚙️ Configuration

Edit `terraform/variables.tf` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | (required) | Your GCP project ID |
| `environment` | `dev` | Environment name (dev/staging/prod) |
| `region` | `us-central1` | GCP region |

---

## 🔧 Required IAM Permissions

The compute service account needs these roles:

| Role | Purpose |
|------|---------|
| `roles/storage.admin` | GCS bucket access |
| `roles/logging.logWriter` | Cloud Logging |
| `roles/batch.agentReporter` | Batch job reporting |
| `roles/iam.serviceAccountTokenCreator` | Token generation |
| `roles/artifactregistry.reader` | Pull container images |
| `roles/bigquery.dataEditor` | Write to BigQuery tables (Variant Transforms) |
| `roles/bigquery.jobUser` | Run BigQuery jobs (Variant Transforms) |

Grant with:
```bash
SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for ROLE in storage.admin logging.logWriter batch.agentReporter \
            iam.serviceAccountTokenCreator artifactregistry.reader \
            bigquery.dataEditor bigquery.jobUser; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA" \
    --role="roles/$ROLE" --quiet
done
```

---

## ✅ Verification

```bash
# Check BigQuery data
bq query --nouse_legacy_sql \
  "SELECT COUNT(*) as variants FROM \`$PROJECT_ID.genomics_warehouse.deepvariant_variants\`"

# List GCS outputs
gsutil ls gs://$PROJECT_ID-results-dev/deepvariant-parallel/
```

---

## 📚 Additional Documentation

- [DEPLOYMENT_LOG.md](DEPLOYMENT_LOG.md) - Detailed deployment history
- [LOOKER_STUDIO_GUIDE.md](LOOKER_STUDIO_GUIDE.md) - Dashboard creation
- [PARALLELIZATION_STRATEGIES.md](PARALLELIZATION_STRATEGIES.md) - Performance optimization
- [VALIDATION_GUIDE.md](VALIDATION_GUIDE.md) - Validation steps
