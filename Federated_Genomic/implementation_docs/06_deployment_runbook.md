# Phase 6: Deployment Runbook

## Quick Reference

Complete step-by-step commands to deploy the Federated Genomic Cloud platform.

---

## Prerequisites Checklist

- [ ] GCP Organization with admin access
- [ ] Billing account linked
- [ ] `gcloud` CLI installed and authenticated
- [ ] Terraform >= 1.0.0
- [ ] Docker installed
- [ ] Python 3.9+

## Step 1: Environment Setup

```bash
export ORG_ID="your-org-id"
export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"

# Authenticate
gcloud auth login
gcloud auth application-default login
```

## Step 2: Create Projects

```bash
for PROJECT in fed-node-us fed-node-eu fed-hub; do
  gcloud projects create $PROJECT --organization=$ORG_ID
  gcloud billing projects link $PROJECT --billing-account=$BILLING_ACCOUNT
done
```

## Step 3: Deploy Infrastructure (Terraform)

```bash
cd terraform

# US Node
terraform workspace new fed-node-us
terraform apply -var="project_id=fed-node-us" -var="region=us-central1" -auto-approve

# EU Node
terraform workspace new fed-node-eu
terraform apply -var="project_id=fed-node-eu" -var="region=europe-west2" -auto-approve

# Hub
terraform workspace new fed-hub
terraform apply -var="project_id=fed-hub" -var="region=asia-southeast1" -auto-approve
```

## Step 4: Apply Security Controls

```bash
# Location policies
gcloud org-policies set-policy us-location-policy.yaml --project=fed-node-us
gcloud org-policies set-policy eu-location-policy.yaml --project=fed-node-eu

# VPC Service Controls (requires org admin)
gcloud access-context-manager perimeters create us-bunker --policy=$ACCESS_POLICY \
  --resources=projects/$(gcloud projects describe fed-node-us --format='value(projectNumber)') \
  --restricted-services=bigquery.googleapis.com,storage.googleapis.com
```

## Step 5: Create Pub/Sub

```bash
gcloud pubsub topics create tff-broadcast --project=fed-hub
gcloud pubsub topics create tff-upload --project=fed-hub
gcloud pubsub subscriptions create sub-node-us --topic=tff-broadcast --project=fed-hub
gcloud pubsub subscriptions create sub-node-eu --topic=tff-broadcast --project=fed-hub
gcloud pubsub subscriptions create sub-hub --topic=tff-upload --project=fed-hub
```

## Step 6: Generate & Load Data

```bash
python src/data/generate_synthetic_data.py --n 1000
bq load --source_format=CSV fed-node-us:hospital_data.patient_genomic_data ./data_us.csv
bq load --source_format=CSV fed-node-eu:hospital_data.patient_genomic_data ./data_eu.csv
```

## Step 7: Build & Deploy Containers

```bash
# Create Artifact Registry
gcloud artifacts repositories create tff-images --repository-format=docker \
  --location=us-central1 --project=fed-hub

# Build and push
docker build -t us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1 .
docker push us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1

# Deploy Cloud Run Jobs
gcloud run jobs create tff-worker-us --project=fed-node-us --region=us-central1 \
  --image=us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1
gcloud run jobs create tff-worker-eu --project=fed-node-eu --region=europe-west2 \
  --image=us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1
gcloud run jobs create tff-server --project=fed-hub --region=asia-southeast1 \
  --image=us-central1-docker.pkg.dev/fed-hub/tff-images/tff-server:v1
```

## Step 8: Execute Training

```bash
# Start workers (they wait for broadcasts)
gcloud run jobs execute tff-worker-us --project=fed-node-us --region=us-central1
gcloud run jobs execute tff-worker-eu --project=fed-node-eu --region=europe-west2

# Start orchestrator
gcloud run jobs execute tff-server --project=fed-hub --region=asia-southeast1
```

## Step 9: Verify Results

```bash
# Check logs
gcloud logging read "resource.type=cloud_run_job" --project=fed-hub --limit=20

# Verify no data egress
gcloud logging read "protoPayload.methodName=storage.objects.create" \
  --project=fed-node-us --limit=10
```

---

→ Proceed to [07_verification_testing.md](./07_verification_testing.md)
