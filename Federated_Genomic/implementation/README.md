# Multiomics Reference Architecture

> **From genomic files to actionable insights in minutes, not days.**

---

## The Problem

Life sciences is drowning in data. Sequencing a human genome now costs less than $200, but **analyzing that data** remains the bottleneck.

| Challenge | Impact |
|-----------|--------|
| **Data is locked in files** | VCF, BAM, FASTQ files sit on servers — impossible to query at scale |
| **HPC queues are slow** | Researchers wait days for cluster time to process samples |
| **Silos block discovery** | Genomic data can't easily join clinical data for insights |
| **AI models need structure** | DeepVariant and AlphaFold require data pipelines, not file shares |

The result: **80% of genomic data is never analyzed**. It's "dark data."

---

## The Solution

This platform transforms genomic data from **files to insights** using a production-ready data flow:

### Production Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WET LAB                                                                    │
│  ┌─────────────┐                                                            │
│  │ Sequencer   │  Illumina, PacBio, ONT                                     │
│  │ (FASTQ out) │                                                            │
│  └──────┬──────┘                                                            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────┐                                                            │
│  │ Local Server│  Runs bcl2fastq, stages data                               │
│  │ (Optional)  │                                                            │
│  └──────┬──────┘                                                            │
└─────────┼───────────────────────────────────────────────────────────────────┘
          │ gsutil cp / Storage Transfer Service
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  CLOUD STORAGE (Landing Zone)                                               │
│  gs://your-project-raw-data/                                                │
│  └── samples/                                                               │
│      ├── SAMPLE001/                                                         │
│      │   ├── SAMPLE001_R1.fastq.gz                                          │
│      │   └── SAMPLE001_R2.fastq.gz                                          │
│      └── SAMPLE002/                                                         │
└─────────┬───────────────────────────────────────────────────────────────────┘
          │ Trigger: Cloud Function / Pub/Sub / Manual
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 1: PROCESS (Cloud Batch + Nextflow)                                  │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐                         │
│  │ Alignment  │───▶│ DeepVariant│───▶│  VCF QC   │                          │
│  │ (BWA-MEM2) │    │   (GPU)    │    │ (bcftools) │                         │
│  └────────────┘    └────────────┘    └────────────┘                         │
│                                                                             │
│  Output: gs://your-project-results/SAMPLE001/SAMPLE001.vcf.gz               │
└─────────┬───────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 2: ANALYZE (BigQuery)                                                │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │ genomics_warehouse.variants                                  │            │
│  │ ┌─────────┬─────────┬─────┬─────┬─────────┬─────────┐       │            │
│  │ │sample_id│chromosome│ pos │ ref │   alt   │ quality │       │            │
│  │ ├─────────┼─────────┼─────┼─────┼─────────┼─────────┤       │            │
│  │ │SAMPLE001│   chr17 │43045│  G  │    A    │   45.2  │       │            │
│  │ └─────────┴─────────┴─────┴─────┴─────────┴─────────┘       │            │
│  └─────────────────────────────────────────────────────────────┘            │
│  Query: "Find BRCA2 carriers in the entire cohort" → 3 seconds              │
└─────────┬───────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 3: VISUALIZE (Looker Studio)                                         │
│  Interactive dashboards for researchers and clinicians                      │
│  - Variant distribution by gene                                             │
│  - Cohort quality metrics                                                   │
│  - Patient-level drill-down                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Expected Bucket Structure

For production deployments, organize your GCS buckets like this:

```
gs://your-project-raw-data/          # Landing zone (from sequencers)
├── samples/
│   ├── SAMPLE001/
│   │   ├── SAMPLE001_R1.fastq.gz
│   │   ├── SAMPLE001_R2.fastq.gz
│   │   └── sample_metadata.json
│   └── SAMPLE002/
└── manifests/
    └── batch_2024-01-15.csv

gs://your-project-results/           # Pipeline outputs
├── aligned/
│   └── SAMPLE001.bam
├── variants/
│   └── SAMPLE001.vcf.gz
└── qc/
    └── SAMPLE001_multiqc.html

gs://your-project-staging/           # Temp files (auto-cleanup)
└── work/
```

> **Demo Mode:** This repository uses [1000 Genomes public data](https://cloud.google.com/life-sciences/docs/resources/public-datasets/1000-genomes) for testing. Replace with your own data paths in production.



---

## Key Capabilities

### 🧬 Scalable Variant Calling
Run DeepVariant on 10 samples or 10,000 — with zero queue time.
- GPU-accelerated on Cloud Batch
- Spot instances for 90% cost savings
- Nextflow for reproducible workflows

### 📊 Queryable Genomic Data
Stop grepping files. Start using SQL.
```sql
-- Find high-quality BRCA1 variants in a cohort
SELECT * FROM genomics_warehouse.variants
WHERE chromosome = 'chr17' 
  AND position BETWEEN 43044295 AND 43170245
  AND quality > 30
```

### 📈 Self-Service Analytics
Interactive dashboards for non-programmers.
- Variant distribution by chromosome
- Quality metrics and filters
- Cohort comparisons

---

## Quick Start

### Demo Mode (Public Data)

```bash
# 1. Deploy infrastructure
cd implementation/terraform
terraform apply -var="project_id=YOUR_PROJECT"

# 2. Run QC on a 1000 Genomes sample
cd ../pipelines
nextflow run main.nf -profile gcp --sample_id HG00119

# 3. Query variants in BigQuery
bq query "SELECT chromosome, COUNT(*) FROM genomics_warehouse.deepvariant_variants GROUP BY chromosome"
```

### Production Mode (Your Data)

```bash
# 1. Upload your data to GCS
gsutil -m cp -r /local/path/SAMPLE001/*.fastq.gz gs://your-project-raw-data/samples/SAMPLE001/

# 2. Run the full pipeline with variant calling
nextflow run main.nf -profile gcp \
    --sample_id SAMPLE001 \
    --input_bam gs://your-project-raw-data/samples/SAMPLE001/SAMPLE001.bam \
    --run_variant_calling true \
    --load_to_bigquery true

# 3. View results in Looker Studio dashboard
# → https://lookerstudio.google.com/your-dashboard-id
```

See [QUICKSTART.md](docs/QUICKSTART.md) for detailed setup instructions.

---

## Architecture

| Component | Purpose | Technology |
|-----------|---------|------------|
| **Compute** | Run bioinformatics pipelines | Cloud Batch, Nextflow |
| **Storage** | Store raw and processed data | Cloud Storage |
| **Analytics** | Query variants at scale | BigQuery |
| **Visualization** | Dashboards for researchers | Looker Studio |
| **AI/ML** | Variant calling, protein folding | DeepVariant, AlphaFold |

---

## Why This Matters

| Before | After |
|--------|-------|
| Days to process a sample | Minutes |
| Can't query variants at scale | SQL on petabytes |
| Data locked in files | Joins with clinical data |
| HPC queue bottlenecks | Elastic, serverless compute |
| Manual reporting | Self-service dashboards |

---

## Documentation

- [Quick Start Guide](docs/QUICKSTART.md) — Step-by-step deployment
- [Nextflow Guide](docs/NEXTFLOW_GUIDE.md) — Pipeline orchestration
- [Looker Studio Guide](docs/LOOKER_STUDIO_GUIDE.md) — Dashboard creation
- [Vision & Strategy](../documentations/1.vision.md) — Project rationale
- [Technical Architecture](../documentations/2.architecture.md) — System design

---

## License

This is a reference architecture for educational and demonstration purposes.

Built with ❤️ on Google Cloud.
