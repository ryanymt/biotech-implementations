# Phase 5: Compute Layer

## Objective

Deploy secure compute infrastructure for federated learning and genomic preprocessing, demonstrating **Confidential Computing**, **Data Sovereignty**, and **Scalability**.

## Deliverables

- [x] Cloud Run Jobs for TFF workers
- [x] Confidential Computing configuration  
- [x] Cloud Batch for scalable preprocessing (see [03a_preprocessing_pipeline.md](./03a_preprocessing_pipeline.md))
- [x] All compute within VPC-SC perimeter

## Compute Options Summary

| Workload | Service | Confidential? | Best For |
|----------|---------|---------------|----------|
| TFF Training | Cloud Run Jobs | Via 2nd Gen | Long-running listeners |
| Genomic Preprocessing | **Cloud Batch** | Yes (AMD SEV) | Parallel batch processing |
| Custom ML | Confidential VMs | Yes | Full control |


---

## 5.1 Confidential Computing Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CONFIDENTIAL VM (AMD SEV)                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Hardware-Encrypted Memory                                    │   │
│  │  • Data encrypted in RAM during processing                   │   │
│  │  • Keys held by CPU, not hypervisor                          │   │
│  │  • Protection from cloud admin access                        │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  TFF Worker Container                                         │   │
│  │  • Loads local BigQuery data                                  │   │
│  │  • Trains model on encrypted memory                          │   │
│  │  • Exports only model weights (gradients)                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## 5.2 Deploy Cloud Run Jobs

### US Node Worker

```bash
gcloud run jobs create tff-worker-us \
  --project=fed-node-us \
  --region=us-central1 \
  --image=us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1 \
  --service-account=node-worker@fed-node-us.iam.gserviceaccount.com \
  --set-env-vars="PROJECT_ID=fed-node-us,HUB_PROJECT=fed-hub,SUBSCRIPTION=sub-node-us,NODE_ID=US" \
  --memory=4Gi \
  --cpu=2 \
  --task-timeout=3600s \
  --max-retries=1
```

### EU Node Worker

```bash
gcloud run jobs create tff-worker-eu \
  --project=fed-node-eu \
  --region=europe-west2 \
  --image=europe-west2-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1 \
  --service-account=node-worker@fed-node-eu.iam.gserviceaccount.com \
  --set-env-vars="PROJECT_ID=fed-node-eu,HUB_PROJECT=fed-hub,SUBSCRIPTION=sub-node-eu,NODE_ID=EU" \
  --memory=4Gi \
  --cpu=2 \
  --task-timeout=3600s \
  --max-retries=1
```

### Hub Orchestrator

```bash
gcloud run jobs create tff-server \
  --project=fed-hub \
  --region=asia-southeast1 \
  --image=asia-southeast1-docker.pkg.dev/fed-hub/tff-images/tff-server:v1 \
  --service-account=hub-orchestrator@fed-hub.iam.gserviceaccount.com \
  --set-env-vars="PROJECT_ID=fed-hub,NUM_NODES=2,NUM_ROUNDS=10" \
  --memory=2Gi \
  --cpu=1 \
  --task-timeout=7200s
```

## 5.3 Confidential VM Alternative

For workloads requiring stronger isolation, use Compute Engine with Confidential Computing:

```bash
gcloud compute instances create tff-worker-confidential \
  --project=fed-node-us \
  --zone=us-central1-a \
  --machine-type=n2d-standard-4 \
  --confidential-compute \
  --maintenance-policy=TERMINATE \
  --image-family=ubuntu-2204-lts \
  --image-project=confidential-vm-images \
  --boot-disk-size=50GB \
  --service-account=node-worker@fed-node-us.iam.gserviceaccount.com \
  --scopes=cloud-platform
```

## 5.4 Execute Training

### Start Workers (keep running to listen for broadcasts)

```bash
# Start US worker
gcloud run jobs execute tff-worker-us --project=fed-node-us --region=us-central1

# Start EU worker
gcloud run jobs execute tff-worker-eu --project=fed-node-eu --region=europe-west2

# Start orchestrator (initiates training)
gcloud run jobs execute tff-server --project=fed-hub --region=asia-southeast1
```

## 5.5 Monitor Execution

```bash
# View logs from hub
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=tff-server" \
  --project=fed-hub --limit=50

# View US node logs
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=tff-worker-us" \
  --project=fed-node-us --limit=50
```

---

→ Proceed to [06_deployment_runbook.md](./06_deployment_runbook.md)
