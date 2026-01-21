# Parallelization Strategies for DeepVariant

This document compares parallelization approaches for DeepVariant variant calling on Google Cloud.

---

## Overview

DeepVariant can be parallelized in multiple ways to reduce wall-clock time for WGS variant calling. This document compares two main approaches for production use.

---

## Option 1: Chromosome Sharding (Cloud Batch Native)

**Concept:** Single Cloud Batch job with multiple tasks, each processing different chromosome regions.

### Architecture
```
Cloud Batch Job (parallelism=4)
├── Task 0: chr1-chr5 → sample_chr1-5.vcf.gz
├── Task 1: chr6-chr10 → sample_chr6-10.vcf.gz
├── Task 2: chr11-chr15 → sample_chr11-15.vcf.gz
└── Task 3: chr16-chrY → sample_chr16-Y.vcf.gz
                ↓
        [Merge Step]
                ↓
        final.vcf.gz
```

### Implementation Files
- `implementation/scripts/deepvariant-parallel-job.json` - Batch job with 4 parallel tasks
- `implementation/scripts/run_deepvariant_parallel.sh` - Per-task runner script
- `implementation/scripts/merge_vcf_shards.sh` - Merge script for final VCF

### Configuration
| Setting | Value |
|---------|-------|
| Tasks | 4 |
| Parallelism | 4 (all run simultaneously) |
| Machine per task | n1-standard-8 (8 vCPU, 32GB RAM) |
| GPU per task | NVIDIA T4 |
| Disk per task | 200GB SSD |

### Pros & Cons
| ✅ Pros | ❌ Cons |
|---------|---------|
| Simple - uses existing Cloud Batch | Only parallelizes single sample |
| No new tools to learn | Need separate merge step |
| Easy to debug (single job) | Less flexible for complex workflows |
| ~4x speedup vs sequential | No built-in retry per chromosome |

### Time Estimate
- Sequential: ~6 hours
- Parallel (4 tasks): ~1.5-2 hours

---

## Option 4: Nextflow + Cloud Batch (Production-Ready)

**Concept:** Use Nextflow as orchestration layer with Cloud Batch executor.

### Architecture
```
Nextflow (Orchestrator)
│
├── Input: sample_sheet.csv (N samples)
│
├── Process: DOWNLOAD_REFERENCE (once)
│
├── Process: DEEPVARIANT (N × 4 parallel)
│   ├── Sample1: chr1-5, chr6-10, chr11-15, chr16-Y
│   ├── Sample2: chr1-5, chr6-10, chr11-15, chr16-Y
│   └── SampleN: ...
│
├── Process: MERGE_VCF (N parallel)
│
└── Output: gs://bucket/results/{sample_id}/final.vcf.gz
```

### Pros & Cons
| ✅ Pros | ❌ Cons |
|---------|---------|
| Scales to cohorts (100s of samples) | Steeper learning curve (Nextflow DSL2) |
| Built-in resume on failure | More files to maintain |
| Industry standard (nf-core) | Requires Nextflow installation |
| Automatic retry per task | |
| Multi-cloud portable | |

### Time Estimate (100 samples)
- Sequential: 600 hours (25 days)
- Nextflow parallel: ~2-3 hours (with sufficient quota)

---

## Comparison Summary

| Criteria | Option 1 (Cloud Batch) | Option 4 (Nextflow) |
|----------|------------------------|---------------------|
| **Target user** | GCP-focused teams | Bioinformatics teams |
| **Industry adoption** | Low | Very High (nf-core) |
| **Implementation time** | 2-3 hours | 6-8 hours |
| **Multi-sample** | Manual job submission | Native (sample sheet) |
| **Failure recovery** | Manual resubmit | Automatic resume |
| **Cloud portability** | GCP only | AWS, Azure, GCP |
| **Best for** | Quick POC, single sample | Production, cohorts |

---

## Recommendation

### For This POC
Use **Option 1 (Chromosome Sharding)** to demonstrate:
- Cloud Batch parallel task execution
- GPU-accelerated variant calling
- ~4x speedup over sequential

### For Production Handoff
Recommend **Option 4 (Nextflow)** because:
1. Most genomics teams already use Nextflow
2. nf-core has proven [nf-core/deepvariant](https://github.com/nf-core/deepvariant) workflow
3. Better for cohort-scale processing (GWAS, population studies)
4. Built-in error recovery and resume capability

---

## Running the Parallelized Job

### Submit Job
```bash
gcloud batch jobs submit deepvariant-parallel-$(date +%H%M%S) \
    --project=multiomnic-ref \
    --location=us-central1 \
    --config=implementation/scripts/deepvariant-parallel-job.json
```

### Monitor Tasks
```bash
gcloud batch jobs describe <JOB_NAME> \
    --project=multiomnic-ref \
    --location=us-central1 \
    --format="yaml(status.taskGroups)"
```

### Merge Shards (after all tasks complete)
```bash
gcloud batch jobs submit merge-vcf-$(date +%H%M%S) \
    --project=multiomnic-ref \
    --location=us-central1 \
    --config=implementation/scripts/merge-job.json
```

---

## Output Location
- Shards: `gs://multiomnic-ref-results-dev/deepvariant-parallel/shards/`
- Final VCF: `gs://multiomnic-ref-results-dev/deepvariant-parallel/HG00119_final.vcf.gz`
