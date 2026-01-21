#!/bin/bash
# =============================================================================
# Cloud-Native Multiomics Platform - Deployment Script
# =============================================================================
# Purpose: Deploy infrastructure and pipelines to Google Cloud
# Usage: ./deploy.sh [phase] [environment]
#        ./deploy.sh all dev          # Full deployment
#        ./deploy.sh infra prod       # Infrastructure only
#        ./deploy.sh validate dev     # Dry run / validation
# =============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
PIPELINES_DIR="$PROJECT_ROOT/pipelines"

# Defaults
PHASE="${1:-all}"
ENVIRONMENT="${2:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo ""
    echo "=============================================="
    echo "  Cloud-Native Multiomics Platform"
    echo "  Deployment: $PHASE | Environment: $ENVIRONMENT"
    echo "=============================================="
    echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install: https://www.terraform.io/downloads"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list 2>&1 | grep -q "ACTIVE"; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Get project ID
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        log_error "No GCP project set. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    log_success "Prerequisites OK. Project: $PROJECT_ID"
}

# =============================================================================
# Deployment Phases
# =============================================================================

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize
    terraform init -upgrade
    
    # Validate
    terraform validate
    
    # Plan
    terraform plan \
        -var="project_id=$PROJECT_ID" \
        -var="environment=$ENVIRONMENT" \
        -out=tfplan
    
    # Apply (with confirmation in interactive mode)
    if [ "$AUTO_APPROVE" = "true" ]; then
        terraform apply tfplan
    else
        echo ""
        read -p "Apply Terraform changes? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            terraform apply tfplan
        else
            log_warn "Terraform apply cancelled"
            return 1
        fi
    fi
    
    # Save outputs
    terraform output -json > "$PROJECT_ROOT/.terraform-outputs.json"
    
    log_success "Infrastructure deployed successfully!"
}

validate_pipelines() {
    log_info "Validating Nextflow pipelines..."
    
    cd "$PIPELINES_DIR"
    
    # Check Nextflow installation
    if ! command -v nextflow &> /dev/null; then
        log_warn "Nextflow not installed. Install with: curl -s https://get.nextflow.io | bash"
        return 1
    fi
    
    # Validate main pipeline
    nextflow run main.nf -preview
    
    log_success "Pipeline validation complete!"
}

test_bigquery_connection() {
    log_info "Testing BigQuery connection..."
    
    # Test query against public data
    bq query --use_legacy_sql=false \
        "SELECT COUNT(*) as variant_count 
         FROM \`bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220\` 
         WHERE reference_name = '17' 
         LIMIT 1"
    
    log_success "BigQuery connection OK!"
}

run_pilot_pipeline() {
    log_info "Running pilot pipeline on 1000 Genomes sample..."
    
    cd "$PIPELINES_DIR"
    
    # Run test profile
    nextflow run main.nf -profile test,gcp \
        --sample_id HG00119 \
        --outdir "gs://${PROJECT_ID}-multiomics-results-${ENVIRONMENT}/pilot-test"
    
    log_success "Pilot pipeline complete!"
}

# =============================================================================
# Main
# =============================================================================

print_banner
check_prerequisites

case "$PHASE" in
    infra|infrastructure)
        deploy_infrastructure
        ;;
    validate)
        cd "$TERRAFORM_DIR"
        terraform init -upgrade
        terraform validate
        terraform plan -var="project_id=$PROJECT_ID" -var="environment=$ENVIRONMENT"
        validate_pipelines
        ;;
    pipelines)
        validate_pipelines
        ;;
    bigquery|bq)
        test_bigquery_connection
        ;;
    pilot|test)
        run_pilot_pipeline
        ;;
    all)
        deploy_infrastructure
        validate_pipelines
        test_bigquery_connection
        log_info "Skipping pilot test in 'all' mode. Run: ./deploy.sh pilot"
        ;;
    *)
        echo "Usage: $0 [phase] [environment]"
        echo ""
        echo "Phases:"
        echo "  infra      - Deploy Terraform infrastructure only"
        echo "  validate   - Validate Terraform and Nextflow (dry run)"
        echo "  pipelines  - Validate Nextflow pipelines"
        echo "  bigquery   - Test BigQuery connection"
        echo "  pilot      - Run pilot pipeline on test data"
        echo "  all        - Full deployment (infra + validation)"
        echo ""
        echo "Environments: dev, staging, prod"
        exit 1
        ;;
esac

echo ""
log_success "Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Review Terraform outputs: cat .terraform-outputs.json"
echo "  2. Run pilot test: ./scripts/deploy.sh pilot $ENVIRONMENT"
echo "  3. Query public data: bq query < bigquery/queries/brca1_variants.sql"
echo ""
