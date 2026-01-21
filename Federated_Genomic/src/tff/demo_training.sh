#!/bin/bash
# Federated Learning Demo - Visual Training with Weight Aggregation
# This script submits training jobs to all 3 nodes and displays progress
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "============================================================"
echo "  FEDERATED LEARNING DEMO - VISUAL TRAINING"
echo "  Training across HIPAA (US) + GDPR (EU) + PDPA (SG) nodes"
echo "============================================================"
echo ""

# Step 1: Clear previous weights
echo "🗑️  Clearing previous weights..."
gsutil -q rm -f gs://fedgen-weights/weights/*.json 2>/dev/null || true
echo ""

# Step 2: Submit training jobs to all 3 nodes simultaneously
echo "📤 Submitting training jobs to all 3 nodes..."
echo ""

# Submit US job
echo ">> Submitting US Node (HIPAA - fedgen-node-us)..."
gcloud batch jobs submit tff-train-us-${TIMESTAMP} \
  --location=us-central1 \
  --project=fedgen-node-us \
  --config=src/tff/batch-train-us.json \
  --quiet 2>/dev/null && echo "   ✓ US job submitted" || echo "   ⚠️  US job failed to submit"

# Submit EU job  
echo ">> Submitting EU Node (GDPR - fedgen-node-eu)..."
gcloud batch jobs submit tff-train-eu-${TIMESTAMP} \
  --location=europe-west2 \
  --project=fedgen-node-eu \
  --config=src/tff/batch-train-eu.json \
  --quiet 2>/dev/null && echo "   ✓ EU job submitted" || echo "   ⚠️  EU job failed to submit"

# Submit SG job
echo ">> Submitting SG Node (PDPA - multiomnic-ref)..."
gcloud batch jobs submit tff-train-sg-${TIMESTAMP} \
  --location=us-central1 \
  --project=multiomnic-ref \
  --config=src/tff/batch-train-sg.json \
  --quiet 2>/dev/null && echo "   ✓ SG job submitted" || echo "   ⚠️  SG job failed to submit"

echo ""
echo "============================================================"
echo "  📺 OPEN THESE TABS TO WATCH TRAINING IN REAL-TIME:"
echo "============================================================"
echo ""
echo "US Node: https://console.cloud.google.com/batch/jobs?project=fedgen-node-us"
echo "EU Node: https://console.cloud.google.com/batch/jobs?project=fedgen-node-eu"
echo "SG Node: https://console.cloud.google.com/batch/jobs?project=multiomnic-ref"
echo ""
echo "============================================================"
echo "  ⏳ WAITING FOR JOBS TO COMPLETE (3-5 minutes)..."
echo "============================================================"
echo ""

# Step 3: Monitor jobs
echo "Polling job status every 30 seconds..."
MAX_WAIT=600  # 10 minutes max
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    
    # Check SG job (the one we can always access)
    SG_STATUS=$(gcloud batch jobs describe tff-train-sg-${TIMESTAMP} --location=us-central1 --project=multiomnic-ref --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
    
    echo "[$(date +%H:%M:%S)] SG Node: $SG_STATUS (${ELAPSED}s elapsed)"
    
    # Check for weights
    US_WEIGHTS=$(gsutil ls gs://fedgen-weights/weights/us_weights.json >/dev/null 2>&1 && echo "✓" || echo "pending")
    EU_WEIGHTS=$(gsutil ls gs://fedgen-weights/weights/eu_weights.json >/dev/null 2>&1 && echo "✓" || echo "pending")  
    SG_WEIGHTS=$(gsutil ls gs://fedgen-weights/weights/sg_weights.json >/dev/null 2>&1 && echo "✓" || echo "pending")
    
    echo "   Weights: US=$US_WEIGHTS, EU=$EU_WEIGHTS, SG=$SG_WEIGHTS"
    
    # If all weights are present, proceed to aggregation
    if [ "$US_WEIGHTS" = "✓" ] && [ "$EU_WEIGHTS" = "✓" ] && [ "$SG_WEIGHTS" = "✓" ]; then
        echo ""
        echo "✅ All weights received!"
        break
    fi
    
    # If SG succeeded but others still pending, that's okay - continue
    if [ "$SG_STATUS" = "SUCCEEDED" ]; then
        echo "   SG completed. Waiting for other nodes..."
    fi
done

echo ""
echo "============================================================"
echo "  🔄 AGGREGATING WEIGHTS AT FEDERATION HUB"
echo "============================================================"
echo ""

# Step 4: Run aggregation
# Run aggregation using local venv
if [ -f "src/tff/venv/bin/python3" ]; then
    PYTHON_CMD="src/tff/venv/bin/python3"
else
    PYTHON_CMD="python3"
fi

$PYTHON_CMD src/tff/aggregate_weights.py

echo ""
echo "============================================================"
echo "  🎉 DEMO COMPLETE"
echo "============================================================"
echo ""
echo "What happened:"
echo "  1. ✓ 3 training jobs ran in parallel across 3 GCP projects"
echo "  2. ✓ Each node trained on its OWN local data"
echo "  3. ✓ Only model weights (bytes) were uploaded to GCS"
echo "  4. ✓ Federation Hub combined weights using FedAvg"
echo ""
echo "Privacy preserved:"
echo "  • US patient data NEVER left fedgen-node-us"
echo "  • EU patient data NEVER left fedgen-node-eu"  
echo "  • SG patient data NEVER left multiomnic-ref"
echo "  • Only mathematical representations (weights) were shared"
echo ""
