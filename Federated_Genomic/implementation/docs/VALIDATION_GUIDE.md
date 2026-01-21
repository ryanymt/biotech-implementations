# Validation Guide - MultiOmnic Reference Architecture

This guide shows how to validate that each component is working and where to find results.

---

## 🔗 Quick Links (Console URLs)

| Component | Console URL |
|-----------|-------------|
| **Project** | https://console.cloud.google.com/home/dashboard?project=multiomnic-ref |
| **Cloud Batch Jobs** | https://console.cloud.google.com/batch/jobs?project=multiomnic-ref |
| **Cloud Storage** | https://console.cloud.google.com/storage/browser?project=multiomnic-ref |
| **BigQuery** | https://console.cloud.google.com/bigquery?project=multiomnic-ref&ws=!1m4!1m3!3m2!1smultiomnic-ref!2sgenomics_warehouse |
| **Logs** | https://console.cloud.google.com/logs?project=multiomnic-ref |
| **Dataflow** | https://console.cloud.google.com/dataflow?project=multiomnic-ref |

---

## 1. Cloud Batch (QC Pipeline, DeepVariant, AlphaFold)

### Where to Check
- **Console:** https://console.cloud.google.com/batch/jobs?project=multiomnic-ref
- **CLI:** `gcloud batch jobs list --project=multiomnic-ref --location=us-central1`

### Job States
| State | Meaning |
|-------|---------|
| QUEUED | Job is waiting for resources |
| SCHEDULED | Resources are being allocated |
| RUNNING | Job is executing |
| SUCCEEDED | Job completed successfully |
| FAILED | Job failed (check logs) |

### View Job Logs
```bash
# List recent jobs
gcloud batch jobs list --project=multiomnic-ref --location=us-central1 --limit=5

# Get job details
gcloud batch jobs describe JOB_NAME --project=multiomnic-ref --location=us-central1

# View logs in console
# Click on job → Tasks → View Logs
```

---

## 2. Cloud Storage (Pipeline Outputs)

### Where to Check
- **Console:** https://console.cloud.google.com/storage/browser?project=multiomnic-ref
- **CLI:** `gsutil ls gs://multiomnic-ref-results-dev/`

### Output Locations
| Pipeline | Output Path |
|----------|-------------|
| QC Pipeline | `gs://multiomnic-ref-results-dev/qc-pilot-YYYYMMDD/` |
| DeepVariant | `gs://multiomnic-ref-results-dev/deepvariant/` |
| AlphaFold | `gs://multiomnic-ref-results-dev/alphafold/` |

### Verify QC Outputs
```bash
# List QC outputs
gsutil ls gs://multiomnic-ref-results-dev/qc-pilot-20260107/qc/

# View flagstat results
gsutil cat gs://multiomnic-ref-results-dev/qc-pilot-20260107/qc/flagstat/HG00119.flagstat.txt

# View idxstats results
gsutil cat gs://multiomnic-ref-results-dev/qc-pilot-20260107/qc/idxstats/HG00119.idxstats.txt
```

---

## 3. BigQuery (Your Dataset)

### Where to Check
- **Console:** https://console.cloud.google.com/bigquery?project=multiomnic-ref
- **Direct Link:** Click `genomics_warehouse` → `brca1_variants`

### Verify Tables
```bash
# List tables in your dataset
bq ls multiomnic-ref:genomics_warehouse

# Show table schema
bq show multiomnic-ref:genomics_warehouse.brca1_variants

# Query sample data
bq head -n 10 multiomnic-ref:genomics_warehouse.brca1_variants
```

### Current Tables
| Table | Rows | Description |
|-------|------|-------------|
| `brca1_variants` | 1,000 | BRCA1 gene variants from 1000 Genomes |

### Sample Query (Run in Console)
```sql
SELECT 
  reference_name,
  start_position,
  reference_bases,
  JSON_EXTRACT_SCALAR(alternate_bases[OFFSET(0)], '$.alt') as alt_allele,
  names[OFFSET(0)] as rsid
FROM `multiomnic-ref.genomics_warehouse.brca1_variants`
LIMIT 10
```

---

## 4. Logs (Debugging)

### Where to Check
- **Console:** https://console.cloud.google.com/logs?project=multiomnic-ref

### Filter by Component
```
# Cloud Batch logs
resource.type="cloud_batch_job"

# Nextflow-specific logs
resource.type="cloud_batch_task"
labels."batch.googleapis.com/job_name"=~"nf-.*"

# Errors only
severity>=ERROR
```

---

## 5. Nextflow (Local Reports)

After running a Nextflow pipeline, check these local files:

| File | Purpose |
|------|---------|
| `.nextflow.log` | Detailed execution log |
| `<outdir>/pipeline_report.html` | Visual execution report |
| `<outdir>/timeline.html` | Task timeline |
| `<outdir>/trace.txt` | Resource usage per task |

### View Nextflow Logs
```bash
# View last pipeline log
tail -100 implementation/pipelines/.nextflow.log

# Check for errors
grep -i error implementation/pipelines/.nextflow.log
```

---

## 6. Quick Validation Commands

### Check Everything
```bash
# 1. BigQuery table
bq query --use_legacy_sql=false \
  "SELECT COUNT(*) as row_count FROM \`multiomnic-ref.genomics_warehouse.brca1_variants\`"

# 2. Storage outputs
gsutil ls -r gs://multiomnic-ref-results-dev/ | head -20

# 3. Recent Batch jobs
gcloud batch jobs list --project=multiomnic-ref --location=us-central1 --limit=5

# 4. APIs enabled
gcloud services list --enabled --project=multiomnic-ref | wc -l
```

---

## Summary: What's Deployed

| Component | Status | Validation |
|-----------|--------|------------|
| ✅ Project | Active | Console dashboard |
| ✅ VPC Network | Created | `gcloud compute networks list` |
| ✅ Storage (3 buckets) | Created | `gsutil ls` |
| ✅ BigQuery Dataset | Has data | Console → BigQuery |
| ✅ QC Outputs | In GCS | `gsutil ls gs://*/qc-pilot-*` |
| ✅ BRCA1 Table | 1,000 rows | `bq head` |
