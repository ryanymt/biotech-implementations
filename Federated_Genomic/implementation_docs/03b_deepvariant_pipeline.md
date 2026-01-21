# Phase 3B: DeepVariant Pipeline Integration

## Objective

Integrate the **DeepVariant** variant calling pipeline into sovereign nodes, enabling production-grade genomic preprocessing while maintaining all three security pillars.

> **Reference**: This phase integrates assets from the [multiomnic-ref](../implementation/) project.

---

## 3B.1 Enhanced Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               SOVEREIGN NODE - Production Genomic Pipeline                   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │  VPC SERVICE CONTROL PERIMETER (No Data Egress)                       │  │
│   │                                                                       │  │
│   │  ┌─────────────┐    ┌──────────────────┐    ┌──────────────────────┐ │  │
│   │  │ Input CRAM  │───▶│   DeepVariant    │───▶│ bcftools + VCF QC    │ │  │
│   │  │ from GCS    │    │   (GPU Batch)    │    │                      │ │  │
│   │  └─────────────┘    └──────────────────┘    └──────────┬───────────┘ │  │
│   │                                                         │             │  │
│   │                                                         ▼             │  │
│   │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│   │  │  BigQuery (CMEK Encrypted)                                      │ │  │
│   │  │  ├── genomics_warehouse.variants (production schema)            │ │  │
│   │  │  └── hospital_data.patient_genomic_data (federated learning)    │ │  │
│   │  └─────────────────────────────────────────────────────────────────┘ │  │
│   └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 3B.2 DeepVariant on Cloud Batch

### GPU-Accelerated Job Configuration

```json
{
  "taskGroups": [{
    "taskSpec": {
      "runnables": [{
        "container": {
          "imageUri": "google/deepvariant:1.6.0-gpu",
          "commands": [
            "/opt/deepvariant/bin/run_deepvariant",
            "--model_type=WGS",
            "--ref=${REFERENCE}",
            "--reads=${INPUT_BAM}",
            "--output_vcf=/mnt/output/${SAMPLE_ID}.vcf.gz",
            "--output_gvcf=/mnt/output/${SAMPLE_ID}.g.vcf.gz",
            "--num_shards=4"
          ]
        }
      }],
      "computeResource": {
        "cpuMilli": 8000,
        "memoryMib": 32768
      },
      "maxRunDuration": "7200s",
      "maxRetryCount": 2
    },
    "taskCount": 1
  }],
  "allocationPolicy": {
    "instances": [{
      "policy": {
        "machineType": "n1-standard-8",
        "accelerators": [{
          "type": "nvidia-tesla-t4",
          "count": 1
        }],
        "provisioningModel": "SPOT"
      },
      "installGpuDrivers": true
    }],
    "location": {
      "allowedLocations": ["regions/us-central1"]
    },
    "network": {
      "networkInterfaces": [{
        "network": "projects/fedgen-node-us/global/networks/fedgen-us-vpc",
        "subnetwork": "projects/fedgen-node-us/regions/us-central1/subnetworks/fedgen-us-subnet",
        "noExternalIpAddress": true
      }]
    }
  }
}
```

### Submit DeepVariant Job

```bash
gcloud batch jobs submit deepvariant-sample-001 \
  --project=fedgen-node-us \
  --location=us-central1 \
  --config=src/preprocessing/deepvariant-batch-job.json
```

## 3B.3 Nextflow Integration (Optional)

For complex multi-sample workflows, use the Nextflow pipeline:

```bash
# From implementation/pipelines directory
nextflow run main.nf -profile gcp \
  --sample_id HG00119 \
  --run_variant_calling true \
  --load_to_bigquery true
```

**Configuration for sovereign nodes** (`nextflow.config`):
```groovy
profiles {
    sovereign {
        google.batch.network = 'fedgen-us-vpc'
        google.batch.subnetwork = 'fedgen-us-subnet'
        google.region = 'us-central1'
        process.machineType = 'n2d-standard-4'  // SEV-compatible
    }
}
```

## 3B.4 BigQuery Variant Schema

Enhanced schema for production variant data:

```sql
CREATE TABLE IF NOT EXISTS `genomics_warehouse.variants`
(
    reference_name      STRING NOT NULL,
    start_position      INT64 NOT NULL,
    end_position        INT64 NOT NULL,
    reference_bases     STRING NOT NULL,
    alternate_bases     ARRAY<STRING> NOT NULL,
    variant_id          STRING,
    quality             FLOAT64,
    filter              ARRAY<STRING>,
    calls               ARRAY<STRUCT<
        sample_id       STRING,
        genotype        ARRAY<INT64>,
        genotype_quality INT64,
        read_depth      INT64
    >>,
    source_file         STRING,
    ingestion_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(ingestion_timestamp)
CLUSTER BY reference_name, start_position;
```

## 3B.5 Data Flow Options

| Source | Method | Best For |
|--------|--------|----------|
| **1000 Genomes** (public) | Reference architecture demo | Validation, testing |
| **Synthetic data** (current) | Generated CSV | Federated learning demos |
| **Customer FASTQ** | DeepVariant pipeline | Production deployment |

## 3B.6 Security Pillars Verification

| Pillar | Implementation | Verification |
|--------|----------------|--------------|
| **Confidential Computing** | GPU jobs on N2D (AMD SEV) | `gcloud compute instances describe --format="confidentialInstanceConfig"` |
| **Data Sovereignty** | Regional GCS + BQ + Org Policy | Job fails if wrong region |
| **Security Controls** | VPC-SC + no external IP | Audit logs show no egress |

---

→ Continue to [04_federation_engine.md](./04_federation_engine.md) for federated learning setup
