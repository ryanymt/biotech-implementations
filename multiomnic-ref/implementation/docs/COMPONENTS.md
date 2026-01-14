# Component Documentation & Cost Estimates

Detailed breakdown of each platform component including compute specs, runtime environment, and estimated costs.

---

##  Cost Summary

| Component | Run Location | Per-Run Cost | Monthly Est. (100 samples) |
|-----------|--------------|--------------|---------------------------|
| Terraform | Local/Cloud Shell | Free | Free |
| QC Pipeline | Cloud Batch | ~$0.05/sample | ~$5 |
| Variant Calling (DeepVariant) | Cloud Batch + GPU | ~$2-5/sample | ~$200-500 |
| Variant Transforms | Dataflow | ~$0.10/VCF | ~$10 |
| BigQuery | Serverless | ~$5/TB scanned | ~$5-20 |
| AlphaFold | Cloud Batch + GPU | ~$5-20/protein | ~$50-200 |
| Storage | Cloud Storage | ~$0.02/GB/month | ~$20-100 |

**Total estimated monthly cost for 100 WGS samples: ~$300-850**

---

## 🏗️Infrastructure Layer

### Terraform (`terraform/*.tf`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Provision all GCP infrastructure (VPC, IAM, Storage, APIs) |
| **Runs On** | Local machine or Cloud Shell |
| **Compute Spec** | None (API calls only) |
| **Runtime** | ~2-5 minutes |
| **Cost** | Free (infrastructure costs apply after provisioning) |

**Resources Created:**
- 3x Cloud Storage buckets (results, staging, reference)
- 1x VPC with private subnet + Cloud NAT
- 4x Service accounts (batch, pipeline, bigquery, vertex)
- 1x BigQuery dataset
- ~15 APIs enabled

---

##  Processing Layer

### QC Pipeline (`pipelines/workflows/qc_pipeline.nf`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Quality control on BAM files (flagstat, stats, idxstats) |
| **Runs On** | Cloud Batch |
| **Compute Spec** | `n1-standard-2` (2 vCPU, 7.5 GB RAM) |
| **Runtime** | ~5-15 min/sample |
| **Cost** | ~$0.05/sample |

**Processes:**
- `SAMTOOLS_FLAGSTAT` - Read mapping statistics
- `SAMTOOLS_STATS` - Comprehensive alignment stats
- `SAMTOOLS_IDXSTATS` - Per-chromosome read counts

---

### Variant Calling - DeepVariant (`vertex_ai/deepvariant_batch.py`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | GPU-accelerated variant calling from BAM → VCF |
| **Runs On** | Cloud Batch with GPU |
| **Compute Spec** | `n1-standard-16` + 1x NVIDIA T4 GPU |
| **Runtime** | ~2-4 hours/30x WGS sample |
| **Cost (Spot)** | ~$2-3/sample |
| **Cost (On-demand)** | ~$5-8/sample |

**Outputs:**
- `{sample}.vcf.gz` - Called variants
- `{sample}.g.vcf.gz` - Genomic VCF (for joint calling)

**Cost Breakdown:**
```
n1-standard-16:  $0.76/hr × 3hr = $2.28
T4 GPU:          $0.35/hr × 3hr = $1.05 (Spot pricing)
                                  -------
                 Total:           ~$3.33/sample
```

---

### Variant Calling - GATK (`pipelines/workflows/variant_calling.nf`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Traditional HaplotypeCaller variant calling |
| **Runs On** | Cloud Batch (CPU only) |
| **Compute Spec** | `n1-standard-16` (16 vCPU, 60 GB RAM) |
| **Runtime** | ~6-12 hours/30x WGS sample |
| **Cost** | ~$5-10/sample |

---

##  Analytics Layer

### Variant Transforms (`scripts/variant_transforms_job.py`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Ingest VCF files into BigQuery |
| **Runs On** | Dataflow (managed Apache Beam) |
| **Compute Spec** | Auto-scaled workers (`n1-standard-16`) |
| **Runtime** | ~10-30 min/VCF (size dependent) |
| **Cost** | ~$0.05-0.20/VCF |

**Dataflow Pricing:**
```
Worker vCPU:    $0.069/hr
Worker RAM:     $0.003/GB/hr
Shuffle:        $0.011/GB
                
Typical job:    ~$0.10-0.20 per VCF file
```

---

### BigQuery (`bigquery/*.sql`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | SQL queries on genomic variants |
| **Runs On** | BigQuery (serverless) |
| **Compute Spec** | N/A (serverless) |
| **Runtime** | Seconds to minutes |
| **Cost** | $5/TB scanned (first 1TB/month free) |

**Tables:**
- `variants` - Genomic variants with annotations
- `samples` - Sample metadata and phenotypes
- `genes` - Gene annotations and constraint scores

**Cost Optimization Tips:**
- Use partitioning (by date) and clustering (by chromosome)
- Select only needed columns
- Use `LIMIT` during development

---

##  Intelligence Layer

### AlphaFold Pipeline (`vertex_ai/alphafold_pipeline.py`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Predict 3D protein structure from sequence |
| **Runs On** | Cloud Batch with A100 GPU |
| **Compute Spec** | `a2-highgpu-1g` (12 vCPU, 85 GB RAM, 1x A100 40GB) |
| **Runtime** | ~30 min - 4 hours/protein (length dependent) |
| **Cost (Spot)** | ~$5-15/protein |
| **Cost (On-demand)** | ~$15-40/protein |

**Outputs:**
- `{protein}.pdb` - Predicted structure
- `{protein}_scores.json` - Confidence metrics

** Database Reality Check:**

AlphaFold requires large reference databases. Options for POC:

| Option | Size | Runtime | Recommendation |
|--------|------|---------|----------------|
| `reduced_dbs` | ~600 GB | 30min-2hr |  **Use for POC** |
| `full_dbs` | ~2.5 TB | 1-4hr | Production only |

**Public Data Sources:**
- Pre-computed structures: [AlphaFold DB](https://alphafold.ebi.ac.uk/) - 200M+ proteins already predicted
- Google public bucket: `gs://alphafold-public-datasets/`

**Cost Breakdown (reduced_dbs, Spot):**
```
a2-highgpu-1g (Spot): ~$1.20/hr × 1hr = $1.20
A100 GPU (Spot):      ~$1.60/hr × 1hr = $1.60
Boot disk (500GB):    ~$0.04/hr × 1hr = $0.04
                                        ------
                      Total:            ~$2.84/protein (short sequence)
```

---

### Vertex AI Workbench (`vertex_ai/workbench/`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Interactive Jupyter notebooks for analysis |
| **Runs On** | Vertex AI Workbench (managed JupyterLab) |
| **Compute Spec** | `n1-standard-4` (4 vCPU, 15 GB RAM) |
| **Runtime** | Hours (interactive sessions) |
| **Cost** | ~$0.19/hr while running |

---

##  Storage

### Cloud Storage Buckets

| Bucket | Purpose | Storage Class | Est. Size | Monthly Cost |
|--------|---------|---------------|-----------|--------------|
| `*-results` | Pipeline outputs | Standard | 50-200 GB | $1-4 |
| `*-staging` | Temp/work files | Standard | 100-500 GB | $2-10 |
| `*-reference` | Reference genomes | Standard | 50-100 GB | $1-2 |

**Pricing:**
- Standard: $0.020/GB/month
- Nearline: $0.010/GB/month (30-day minimum)
- Coldline: $0.004/GB/month (90-day minimum)

---

##  Utility Scripts

### Deploy Script (`scripts/deploy.sh`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Automate infrastructure deployment |
| **Runs On** | Local machine |
| **Cost** | Free |

### Pipeline Runner (`scripts/run_pipeline.py`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | CLI wrapper for Nextflow pipelines |
| **Runs On** | Local machine |
| **Cost** | Free (pipeline costs apply) |

### Org Policy Tool (`scripts/export_apply_org_policies.sh`)

| Attribute | Value |
|-----------|-------|
| **Purpose** | Export/apply org policies between projects |
| **Runs On** | Local machine |
| **Cost** | Free |

---

##  Scaling Considerations

| Scale | Samples/Month | Est. Monthly Cost | Notes |
|-------|---------------|-------------------|-------|
| **Pilot** | 10 | $50-100 | Development/testing |
| **Small** | 100 | $300-850 | Small research team |
| **Medium** | 1,000 | $2,500-7,000 | Department-level |
| **Large** | 10,000 | $20,000-60,000 | Enterprise/production |

**Cost Optimization Strategies:**
1. **Use Spot VMs** - 60-90% savings on compute
2. **Right-size instances** - Don't over-provision
3. **Lifecycle policies** - Auto-delete staging data after 30 days
4. **Reserved capacity** - Committed use discounts for steady workloads
5. **BigQuery slots** - Flat-rate pricing for heavy query workloads
