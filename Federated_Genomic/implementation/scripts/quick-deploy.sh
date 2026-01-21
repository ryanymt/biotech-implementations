#!/bin/bash
# =============================================================================
# Multiomics Platform - Quick Deploy Script
# =============================================================================
# One-command deployment of the entire platform
# Usage: ./quick-deploy.sh [environment]
#        ./quick-deploy.sh dev
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENVIRONMENT="${1:-dev}"

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
    error "No project set. Run: gcloud config set project YOUR_PROJECT_ID"
fi

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
REGION="us-central1"

echo ""
echo "========================================================"
echo "  Multiomics Platform - Quick Deploy"
echo "  Project: $PROJECT_ID"
echo "  Environment: $ENVIRONMENT"
echo "========================================================"
echo ""

# =============================================================================
# Phase 1: Enable APIs
# =============================================================================

log "Phase 1: Enabling APIs..."

APIS=(
    "compute.googleapis.com"
    "batch.googleapis.com"
    "bigquery.googleapis.com"
    "storage.googleapis.com"
    "artifactregistry.googleapis.com"
    "cloudbuild.googleapis.com"
    "dataflow.googleapis.com"
    "logging.googleapis.com"
)

for api in "${APIS[@]}"; do
    gcloud services enable $api --project=$PROJECT_ID --quiet 2>/dev/null || true
done
success "APIs enabled"

# =============================================================================
# Phase 2: Deploy Infrastructure (Terraform)
# =============================================================================

log "Phase 2: Deploying infrastructure..."

cd "$PROJECT_ROOT/terraform"

terraform init -upgrade -input=false
terraform apply \
    -var="project_id=$PROJECT_ID" \
    -var="environment=$ENVIRONMENT" \
    -auto-approve

terraform output -json > "$PROJECT_ROOT/.terraform-outputs.json"
success "Infrastructure deployed"

# =============================================================================
# Phase 3: Grant IAM Permissions
# =============================================================================

log "Phase 3: Granting IAM permissions..."

ROLES=(
    "roles/storage.admin"
    "roles/logging.logWriter"
    "roles/batch.agentReporter"
    "roles/iam.serviceAccountTokenCreator"
    "roles/artifactregistry.reader"
    "roles/bigquery.dataEditor"
)

for role in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$COMPUTE_SA" \
        --role="$role" \
        --quiet 2>/dev/null || true
done
success "IAM permissions granted"

# =============================================================================
# Phase 4: Create Artifact Registry & Build Container
# =============================================================================

log "Phase 4: Setting up Artifact Registry..."

# Create repository if not exists
gcloud artifacts repositories describe genomics-containers \
    --project=$PROJECT_ID --location=$REGION 2>/dev/null || \
gcloud artifacts repositories create genomics-containers \
    --project=$PROJECT_ID \
    --location=$REGION \
    --repository-format=docker \
    --description="Genomics container images"

# Grant push permission
gcloud artifacts repositories add-iam-policy-binding genomics-containers \
    --project=$PROJECT_ID \
    --location=$REGION \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/artifactregistry.admin" \
    --quiet 2>/dev/null || true

# Check if image already exists
if gcloud artifacts docker images describe \
    us-central1-docker.pkg.dev/$PROJECT_ID/genomics-containers/gcp-variant-transforms:latest \
    --project=$PROJECT_ID 2>/dev/null; then
    success "Variant Transforms container already exists"
else
    log "Building Variant Transforms container (this takes ~10 min)..."
    
    # Clone and build
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    git clone --depth 1 https://github.com/googlegenomics/gcp-variant-transforms.git
    cd gcp-variant-transforms
    
    # Create custom cloudbuild
    cat > cloudbuild_ar.yaml << EOF
substitutions:
  _REGION: 'us-central1'
  _REPOSITORY: 'genomics-containers'
  _TAG: 'latest'
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '--tag=\${_REGION}-docker.pkg.dev/\$PROJECT_ID/\${_REPOSITORY}/gcp-variant-transforms:\${_TAG}'
      - '--file=docker/Dockerfile'
      - '.'
images:
  - '\${_REGION}-docker.pkg.dev/\$PROJECT_ID/\${_REPOSITORY}/gcp-variant-transforms:\${_TAG}'
timeout: 3600s
EOF
    
    gcloud builds submit --config=cloudbuild_ar.yaml --project=$PROJECT_ID .
    cd "$PROJECT_ROOT"
    rm -rf "$TEMP_DIR"
    success "Variant Transforms container built"
fi

# =============================================================================
# Phase 5: Update Job Configs with Project ID
# =============================================================================

log "Phase 5: Updating job configurations..."

cd "$PROJECT_ROOT/scripts"

# Update project references in batch job files
for f in *.json; do
    sed -i.bak "s/multiomnic-ref/${PROJECT_ID}/g" "$f" 2>/dev/null || \
    sed -i '' "s/multiomnic-ref/${PROJECT_ID}/g" "$f"
done
rm -f *.bak

success "Job configurations updated"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "========================================================"
echo "  Deployment Complete!"
echo "========================================================"
echo ""
echo "Resources created:"
echo "  • VPC: multiomics-vpc"
echo "  • Buckets: gs://${PROJECT_ID}-{results,staging,reference}-${ENVIRONMENT}"
echo "  • BigQuery: ${PROJECT_ID}.genomics_warehouse"
echo "  • Artifact Registry: genomics-containers"
echo "  • Container: gcp-variant-transforms:latest"
echo ""
echo "Next steps:"
echo "  1. Run DeepVariant:"
echo "     gcloud batch jobs submit dv-\$(date +%H%M%S) \\"
echo "       --project=$PROJECT_ID --location=us-central1 \\"
echo "       --config=scripts/deepvariant-parallel-job.json"
echo ""
echo "  2. After DeepVariant (~3h), merge VCF:"
echo "     gcloud batch jobs submit merge-\$(date +%H%M%S) \\"
echo "       --project=$PROJECT_ID --location=us-central1 \\"
echo "       --config=scripts/merge-vcf-job.json"
echo ""
echo "  3. Load to BigQuery:"
echo "     gcloud batch jobs submit vt-\$(date +%H%M%S) \\"
echo "       --project=$PROJECT_ID --location=us-central1 \\"
echo "       --config=scripts/variant-transforms-job.json"
echo ""
echo "See docs/QUICKSTART.md for full details."
echo ""
