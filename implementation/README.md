# Multiomics Reference Architecture

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

###  Scalable Variant Calling
Run DeepVariant on 10 samples or 10,000 — with zero queue time.

###  Queryable Genomic Data

###  Self-Service Analytics
Interactive dashboards for non-programmers.

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



## License

This is a reference architecture for educational and demonstration purposes.

