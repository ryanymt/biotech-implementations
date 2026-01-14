# Nextflow Pipeline Guide

This guide explains how to run genomic analysis workflows using **Nextflow** or **manual Cloud Batch jobs**.

---

## Overview

| Approach | Best For | Complexity |
|----------|----------|------------|
| **Nextflow** | Bioinformaticians, reproducible workflows, multi-step pipelines | Medium |
| **Manual Cloud Batch** | Quick testing, single-step jobs, debugging | Low |

---

## Option 1: Nextflow on Cloud Batch

### Prerequisites

```bash
# Install Nextflow
curl -s https://get.nextflow.io | bash
mv nextflow /usr/local/bin/

# Authenticate with GCP
gcloud auth application-default login
```

### Quick Start

```bash
cd implementation/pipelines

# Run QC only (default, uses public 1000 Genomes data)
nextflow run main.nf -profile gcp --sample_id HG00119

# Run full pipeline with variant calling + BigQuery loading
nextflow run main.nf -profile gcp \
    --sample_id HG00119 \
    --run_variant_calling true \
    --load_to_bigquery true
```

### Available Workflows

| Workflow | Description | Flag |
|----------|-------------|------|
| QC Pipeline | FastQC, MultiQC | Default (use `--skip_qc` to skip) |
| Variant Calling | DeepVariant or GATK | `--run_variant_calling true` |
| VCF to BigQuery | Load variants for analysis | `--load_to_bigquery true` |

### Pipeline Options

```bash
nextflow run main.nf -profile gcp \
    --sample_id MY_SAMPLE \
    --input_bam gs://my-bucket/sample.bam \
    --reference gs://genomics-public-data/resources/broad/hg38/v0/Homo_sapiens_assembly38.fasta \
    --outdir gs://multiomnic-ref-results-dev/outputs \
    --run_variant_calling true \
    --use_deepvariant true \
    --load_to_bigquery true
```

### Monitor & Resume

```bash
# View running jobs
gcloud batch jobs list --project=multiomnic-ref --location=us-central1

# Resume a failed run (skips completed steps)
nextflow run main.nf -profile gcp --sample_id HG00119 -resume
```

---

## Option 2: Manual Cloud Batch Jobs

For single-step execution or debugging, use Cloud Batch directly.

### DeepVariant Variant Calling

```bash
# Run DeepVariant on a sample
gcloud batch jobs submit deepvariant-$(date +%Y%m%d-%H%M%S) \
    --project=multiomnic-ref \
    --location=us-central1 \
    --config=implementation/scripts/deepvariant-job.json
```

### VCF to BigQuery (bcftools approach)

```bash
# Extract variants and load to BigQuery
gcloud batch jobs submit vcf-to-bq-$(date +%Y%m%d-%H%M%S) \
    --project=multiomnic-ref \
    --location=us-central1 \
    --config=implementation/scripts/vcf-to-bigquery-job.json

# Then load the TSV to BigQuery manually:
bq load --source_format=CSV --field_delimiter=tab --skip_leading_rows=1 \
    genomics_warehouse.deepvariant_variants \
    gs://multiomnic-ref-results-dev/deepvariant-parallel/variants_for_bq.tsv
```

### Monitor Jobs

```bash
# Check job status
gcloud batch jobs describe JOB_NAME \
    --project=multiomnic-ref --location=us-central1 \
    --format="yaml(status.state)"

# View logs
gcloud logging read 'logName=~"batch_task_logs"' \
    --project=multiomnic-ref --limit=50 --format="value(textPayload)"
```

---

## Comparison

| Feature | Nextflow | Manual Cloud Batch |
|---------|----------|-------------------|
| Automatic parallelization | ✅ | ❌ |
| Resume from failure | ✅ | ❌ |
| Multi-step pipelines | ✅ | ⚠️ Manual orchestration |
| Caching | ✅ | ❌ |
| Portability (AWS/local) | ✅ | ❌ |
| Quick one-off jobs | ⚠️ | ✅ |
| Debugging | ⚠️ | ✅ |

---

## Pipeline DAG

```
┌─────────────────────────────────────────────────────────┐
│                    INPUT (BAM/FASTQ)                    │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    QC_PIPELINE                          │
│  - SAMTOOLS_STATS                                       │
│  - SAMTOOLS_FLAGSTAT                                    │
│  - MULTIQC                                              │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                 VARIANT_CALLING                         │
│  - DEEPVARIANT_CALL_VARIANTS (GPU)                      │
│  - VCF_STATS                                            │
│  - FILTER_VARIANTS                                      │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  VCF_TO_BIGQUERY                        │
│  - VCF_TO_TSV (bcftools)                                │
│  - UPLOAD_TO_GCS                                        │
│  - LOAD_TO_BIGQUERY                                     │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                   BIGQUERY TABLE                        │
│            genomics_warehouse.deepvariant_variants      │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                 LOOKER STUDIO DASHBOARD                 │
└─────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### Nextflow Issues

```bash
# Clean cache and retry
nextflow clean -f
nextflow run main.nf -profile gcp --sample_id HG00119

# Check Nextflow logs
cat .nextflow.log
```

### Cloud Batch Issues

```bash
# Check for permission issues
gcloud projects get-iam-policy multiomnic-ref --format=json | jq '.bindings[] | select(.role | contains("batch"))'

# View detailed job logs
gcloud logging read 'resource.type="batch.googleapis.com/Job"' \
    --project=multiomnic-ref --limit=20
```
