# Phase 1: Infrastructure Setup

## Objective

Deploy the foundational Google Cloud infrastructure for the Federated Genomic platform, including three isolated GCP projects that simulate a multi-institutional research consortium.

## Deliverables

- [x] 3 GCP Projects created and configured
- [x] APIs enabled in all projects
- [x] Terraform state backend configured
- [x] Base networking deployed

---

## 1.1 Project Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Google Cloud Organization                            │
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │  fed-node-us    │  │  fed-node-eu    │  │  fed-hub        │          │
│  │  └─ us-central1 │  │  └─ europe-west2│  │  └─ asia-se1    │          │
│  │  Role: US Data  │  │  Role: EU Data  │  │  Role: Central  │          │
│  │  Bunker (HIPAA) │  │  Bunker (GDPR)  │  │  Orchestrator   │          │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

## 1.2 Project Creation

### Option A: Manual Creation (Console)

1. Navigate to [Google Cloud Console](https://console.cloud.google.com)
2. Create three projects:
   - `fed-node-us` - US Sovereign Node
   - `fed-node-eu` - EU Sovereign Node  
   - `fed-hub` - Federation Hub

### Option B: gcloud CLI

```bash
# Set your organization and billing account
export ORG_ID="your-org-id"
export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"

# Create US Node
gcloud projects create fed-node-us \
  --organization=$ORG_ID \
  --name="Federated Node US"
gcloud billing projects link fed-node-us --billing-account=$BILLING_ACCOUNT

# Create EU Node
gcloud projects create fed-node-eu \
  --organization=$ORG_ID \
  --name="Federated Node EU"
gcloud billing projects link fed-node-eu --billing-account=$BILLING_ACCOUNT

# Create Hub
gcloud projects create fed-hub \
  --organization=$ORG_ID \
  --name="Federation Hub"
gcloud billing projects link fed-hub --billing-account=$BILLING_ACCOUNT
```

### Option C: Using the Export/Apply Script

```bash
# If you have an existing reference project with org policies
./export_apply_org_policies.sh \
  --source lifescience-project-469915 \
  --create-new fed-node-us \
  --billing $BILLING_ACCOUNT
```

## 1.3 Enable Required APIs

Enable APIs in **all three projects**:

```bash
# API list for all projects
APIS=(
  "compute.googleapis.com"
  "run.googleapis.com"
  "batch.googleapis.com"
  "bigquery.googleapis.com"
  "pubsub.googleapis.com"
  "artifactregistry.googleapis.com"
  "cloudkms.googleapis.com"
  "secretmanager.googleapis.com"
  "logging.googleapis.com"
  "monitoring.googleapis.com"
  "iam.googleapis.com"
  "iamcredentials.googleapis.com"
  "servicenetworking.googleapis.com"
  "accesscontextmanager.googleapis.com"
)

# Enable for each project
for PROJECT in fed-node-us fed-node-eu fed-hub; do
  echo "Enabling APIs for $PROJECT..."
  for API in "${APIS[@]}"; do
    gcloud services enable $API --project=$PROJECT
  done
done
```

## 1.4 Terraform Deployment

### Directory Structure

```
terraform/
├── main.tf           # Provider config, locals
├── variables.tf      # Input variables
├── apis.tf           # API enablement
├── networking.tf     # VPC, subnets, NAT
├── storage.tf        # GCS buckets
├── iam.tf            # Service accounts
└── outputs.tf        # Output values
```

### Initialize and Deploy

```bash
cd terraform

# Initialize Terraform
terraform init

# Deploy US Node
terraform workspace new fed-node-us
terraform plan \
  -var="project_id=fed-node-us" \
  -var="region=us-central1" \
  -var="environment=dev"
terraform apply

# Deploy EU Node
terraform workspace new fed-node-eu
terraform plan \
  -var="project_id=fed-node-eu" \
  -var="region=europe-west2" \
  -var="environment=dev"
terraform apply

# Deploy Hub
terraform workspace new fed-hub
terraform plan \
  -var="project_id=fed-hub" \
  -var="region=asia-southeast1" \
  -var="environment=dev"
terraform apply
```

### Key Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | (required) | GCP project ID |
| `region` | us-central1 | Primary region |
| `environment` | dev | Environment (dev/staging/prod) |
| `storage_location` | US | GCS bucket location |
| `use_spot_vms` | true | Use Spot VMs for cost savings |
| `bigquery_dataset_id` | genomics_warehouse | BigQuery dataset name |

## 1.5 Remote State Configuration

For production, configure GCS backend for Terraform state:

```hcl
# In main.tf, uncomment and configure:
terraform {
  backend "gcs" {
    bucket  = "fed-terraform-state"
    prefix  = "terraform/state"
  }
}
```

Create the state bucket first:

```bash
gcloud storage buckets create gs://fed-terraform-state \
  --project=fed-hub \
  --location=US \
  --uniform-bucket-level-access
```

## 1.6 Verification Checklist

| Check | Command | Expected Result |
|-------|---------|-----------------|
| Projects exist | `gcloud projects list --filter="project_id:fed-*"` | 3 projects listed |
| APIs enabled | `gcloud services list --project=fed-node-us` | All APIs active |
| Billing linked | `gcloud billing projects describe fed-node-us` | Billing account shown |
| VPC created | `gcloud compute networks list --project=fed-node-us` | VPC network listed |

## 1.7 Cost Estimates (POC)

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| 3x Projects (no usage) | $0 |
| Terraform state bucket | ~$0.01 |
| API calls | ~$0 |
| **Phase 1 Total** | **~$0** |

> **Note:** Costs increase significantly in later phases when compute and storage are added.

---

## Next Steps

→ Proceed to [02_security_controls.md](./02_security_controls.md) to configure VPC Service Controls and Organization Policies.
