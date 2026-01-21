#!/bin/bash
# =============================================================================
# Federated Learning Demo - Cross-Project Setup
# =============================================================================
# This script configures the necessary permissions for the 3-node federated
# learning demo to work across:
#   - fedgen-node-us (HIPAA)
#   - fedgen-node-eu (GDPR)
#   - multiomnic-ref (PDPA/Singapore)
#
# Run this once before running the demo.
# =============================================================================

set -e

echo "============================================================"
echo "  FEDERATED DEMO - CROSS-PROJECT SETUP"
echo "============================================================"
echo ""

# Configuration
HUB_PROJECT="multiomnic-ref"
HUB_REGION="us-central1"
ARTIFACT_REPO="genomics-containers"
WEIGHTS_BUCKET="fedgen-weights"

US_PROJECT="fedgen-node-us"
EU_PROJECT="fedgen-node-eu"

# Get service accounts
US_BATCH_SA="batch-runner@${US_PROJECT}.iam.gserviceaccount.com"
EU_BATCH_SA="batch-runner@${EU_PROJECT}.iam.gserviceaccount.com"
US_COMPUTE_SA=$(gcloud projects describe ${US_PROJECT} --format="value(projectNumber)")-compute@developer.gserviceaccount.com
EU_COMPUTE_SA=$(gcloud projects describe ${EU_PROJECT} --format="value(projectNumber)")-compute@developer.gserviceaccount.com

echo ">> Granting Artifact Registry access..."

# Grant container pull permissions
for SA in "$US_BATCH_SA" "$EU_BATCH_SA" "$US_COMPUTE_SA" "$EU_COMPUTE_SA"; do
    echo "   Granting to $SA"
    gcloud artifacts repositories add-iam-policy-binding ${ARTIFACT_REPO} \
        --location=${HUB_REGION} \
        --project=${HUB_PROJECT} \
        --member="serviceAccount:${SA}" \
        --role="roles/artifactregistry.reader" \
        --quiet 2>/dev/null || echo "   (already granted)"
done

echo ""
echo ">> Creating weights bucket (if needed)..."
gsutil ls -p ${HUB_PROJECT} gs://${WEIGHTS_BUCKET} 2>/dev/null || \
    gsutil mb -p ${HUB_PROJECT} -l ${HUB_REGION} gs://${WEIGHTS_BUCKET}

echo ""
echo ">> Granting GCS bucket access..."

# Grant bucket write permissions
for SA in "$US_BATCH_SA" "$EU_BATCH_SA" "$US_COMPUTE_SA" "$EU_COMPUTE_SA"; do
    echo "   Granting to $SA"
    gsutil iam ch serviceAccount:${SA}:objectCreator,objectViewer gs://${WEIGHTS_BUCKET} 2>/dev/null || echo "   (already granted)"
done

echo ""
echo ">> Verifying batch job service account roles..."

# Grant BigQuery access in US project
echo "   US: BigQuery access"
gcloud projects add-iam-policy-binding ${US_PROJECT} \
    --member="serviceAccount:${US_BATCH_SA}" \
    --role="roles/bigquery.dataViewer" \
    --quiet 2>/dev/null
gcloud projects add-iam-policy-binding ${US_PROJECT} \
    --member="serviceAccount:${US_BATCH_SA}" \
    --role="roles/bigquery.jobUser" \
    --quiet 2>/dev/null

# Grant BigQuery access in EU project
echo "   EU: BigQuery access"
gcloud projects add-iam-policy-binding ${EU_PROJECT} \
    --member="serviceAccount:${EU_BATCH_SA}" \
    --role="roles/bigquery.dataViewer" \
    --quiet 2>/dev/null
gcloud projects add-iam-policy-binding ${EU_PROJECT} \
    --member="serviceAccount:${EU_BATCH_SA}" \
    --role="roles/bigquery.jobUser" \
    --quiet 2>/dev/null

echo ""
echo "============================================================"
echo "  ✅ SETUP COMPLETE"
echo "============================================================"
echo ""
echo "The following has been configured:"
echo "  • US/EU service accounts can pull from ${HUB_PROJECT} Artifact Registry"
echo "  • US/EU service accounts can write to gs://${WEIGHTS_BUCKET}"
echo "  • Batch runners have BigQuery access in their respective projects"
echo ""
echo "You can now run the federated demo:"
echo "  bash src/tff/demo_training.sh"
echo ""
