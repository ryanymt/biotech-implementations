# Phase 3A: Genomic Preprocessing Pipeline (Cloud Batch)

## Objective

Demonstrate **Cloud Batch** for scalable genomic data preprocessing while maintaining all three security pillars: **Confidential Computing**, **Data Sovereignty**, and **Security Controls**.

---

## 3A.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               SOVEREIGN NODE (US or EU) - Cloud Batch Pipeline              │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │  VPC SERVICE CONTROL PERIMETER (No Data Egress)                       │  │
│   │                                                                       │  │
│   │  ┌─────────────┐    ┌─────────────────────────────────────────────┐  │  │
│   │  │ Input GCS   │    │   CLOUD BATCH JOB                           │  │  │
│   │  │ (Raw VCFs)  │───▶│   • 50 Parallel Tasks                       │  │  │
│   │  │ Regional    │    │   • Confidential VMs (AMD SEV)              │  │  │
│   │  └─────────────┘    │   • N2D machine type                        │  │  │
│   │                     │                                              │  │  │
│   │                     │   Task: bcftools → VEP → BigQuery Load      │  │  │
│   │                     └─────────────────────────────────────────────┘  │  │
│   │                                   │                                   │  │
│   │                                   ▼                                   │  │
│   │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│   │  │  BigQuery (CMEK Encrypted) - Same Region                        │ │  │
│   │  └─────────────────────────────────────────────────────────────────┘ │  │
│   └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3A.2 Security Pillars Demonstrated

| Pillar | Implementation | Verification |
|--------|----------------|--------------|
| **Confidential Computing** | `--confidential-compute` flag on Batch VMs | Memory encrypted by AMD SEV |
| **Data Sovereignty** | Regional GCS + Regional BigQuery + Org Policy | Data never leaves region |
| **Security Controls** | VPC-SC perimeter + No public IP + IAM | No egress to internet |

---

## 3A.3 Cloud Batch Job Configuration

### Job Specification (`batch-preprocess-job.json`)

```json
{
  "taskGroups": [{
    "taskSpec": {
      "runnables": [{
        "container": {
          "imageUri": "us-central1-docker.pkg.dev/fed-node-us/genomics/vcf-processor:v1",
          "commands": [
            "/bin/bash", "-c",
            "bcftools norm -m -any ${INPUT_VCF} -o /tmp/normalized.vcf && python load_to_bq.py /tmp/normalized.vcf"
          ]
        }
      }],
      "computeResource": {
        "cpuMilli": 4000,
        "memoryMib": 8192
      },
      "maxRunDuration": "3600s"
    },
    "taskCount": 50,
    "parallelism": 50
  }],
  "allocationPolicy": {
    "instances": [{
      "policy": {
        "machineType": "n2d-standard-4",
        "provisioningModel": "SPOT"
      },
      "installGpuDrivers": false
    }],
    "location": {
      "allowedLocations": ["regions/us-central1"]
    },
    "network": {
      "networkInterfaces": [{
        "network": "projects/fed-node-us/global/networks/fed-node-us-multiomics-vpc",
        "subnetwork": "projects/fed-node-us/regions/us-central1/subnetworks/fed-node-us-compute-subnet",
        "noExternalIpAddress": true
      }]
    },
    "serviceAccount": {
      "email": "batch-runner@fed-node-us.iam.gserviceaccount.com"
    }
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
```

### Enable Confidential Computing

```json
{
  "allocationPolicy": {
    "instances": [{
      "policy": {
        "machineType": "n2d-standard-4",
        "confidentialInstanceConfig": {
          "enableConfidentialCompute": true
        }
      }
    }]
  }
}
```

## 3A.4 Container Image

### Dockerfile

```dockerfile
FROM google/cloud-sdk:slim

# Install genomics tools
RUN apt-get update && apt-get install -y \
    bcftools \
    tabix \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install google-cloud-bigquery pandas

COPY scripts/load_to_bq.py /app/
WORKDIR /app

ENTRYPOINT ["/bin/bash"]
```

### BigQuery Loader Script (`load_to_bq.py`)

```python
#!/usr/bin/env python3
"""Load processed VCF to BigQuery within sovereign region."""

import os
import sys
from google.cloud import bigquery

PROJECT_ID = os.environ['PROJECT_ID']
DATASET = 'hospital_data'
TABLE = 'processed_variants'

def load_vcf_to_bq(vcf_path: str):
    client = bigquery.Client(project=PROJECT_ID)
    table_ref = f"{PROJECT_ID}.{DATASET}.{TABLE}"
    
    # Parse VCF and load (simplified)
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND
    )
    
    with open(vcf_path, 'rb') as f:
        job = client.load_table_from_file(f, table_ref, job_config=job_config)
    
    job.result()
    print(f"Loaded {vcf_path} to {table_ref}")

if __name__ == "__main__":
    load_vcf_to_bq(sys.argv[1])
```

## 3A.5 Deployment Commands

### Build and Push Container

```bash
# Build in sovereign region
cd src/preprocessing
docker build -t us-central1-docker.pkg.dev/fed-node-us/genomics/vcf-processor:v1 .

# Push to regional Artifact Registry
docker push us-central1-docker.pkg.dev/fed-node-us/genomics/vcf-processor:v1
```

### Submit Batch Job

```bash
# Submit job - stays within US region perimeter
gcloud batch jobs submit preprocess-genomes-001 \
  --project=fed-node-us \
  --location=us-central1 \
  --config=batch-preprocess-job.json
```

### Monitor Job

```bash
# Check job status
gcloud batch jobs describe preprocess-genomes-001 \
  --project=fed-node-us \
  --location=us-central1

# View logs
gcloud logging read "resource.type=cloud_batch_job" \
  --project=fed-node-us --limit=50
```

## 3A.6 Data Sovereignty Enforcement

### Org Policy Verification

```bash
# Verify Cloud Batch respects location constraints
# This MUST fail - trying to run batch job in wrong region
gcloud batch jobs submit test-wrong-region \
  --project=fed-node-us \
  --location=europe-west2 \
  --config=batch-preprocess-job.json

# Expected: ERROR: Request violates constraint 'gcp.resourceLocations'
```

### VPC-SC Verification

```bash
# Verify batch workers cannot exfiltrate data
# Check that no data left the perimeter
gcloud logging read \
  'protoPayload.methodName="storage.objects.create" AND NOT resource.labels.bucket_name:fed-node-us' \
  --project=fed-node-us --limit=10

# Expected: No results (all writes stayed within project)
```

## 3A.7 Confidential Computing Verification

```bash
# Verify Confidential VMs were used
gcloud logging read \
  'resource.type="gce_instance" AND protoPayload.request.confidentialInstanceConfig.enableConfidentialCompute=true' \
  --project=fed-node-us --limit=10

# Check AMD SEV status on running instances
gcloud compute instances describe INSTANCE_NAME \
  --zone=us-central1-a \
  --format="value(confidentialInstanceConfig)"
```

## 3A.8 Scalability Demonstration

| Scenario | Tasks | VMs | Duration |
|----------|-------|-----|----------|
| Small POC | 10 VCFs | 10 | ~5 min |
| Medium | 100 VCFs | 50 | ~10 min |
| Production | 1000 VCFs | 100 | ~20 min |

```bash
# Scale up by modifying taskCount
jq '.taskGroups[0].taskCount = 100 | .taskGroups[0].parallelism = 100' \
  batch-preprocess-job.json > batch-preprocess-job-100.json

gcloud batch jobs submit preprocess-genomes-100 \
  --project=fed-node-us \
  --location=us-central1 \
  --config=batch-preprocess-job-100.json
```

---

## Summary

This Cloud Batch preprocessing pipeline demonstrates:
- ✅ **Scalability**: Process 1000s of genomes in parallel with Spot VMs
- ✅ **Confidential Computing**: All processing on AMD SEV encrypted memory
- ✅ **Data Sovereignty**: Regional constraints enforced by Org Policies
- ✅ **Security**: VPC-SC blocks all data egress, no public IPs

→ Continue to [04_federation_engine.md](./04_federation_engine.md)
