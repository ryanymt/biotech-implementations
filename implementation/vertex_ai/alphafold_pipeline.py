#!/usr/bin/env python3
"""
=============================================================================
AlphaFold Pipeline for Vertex AI / Cloud Batch
=============================================================================
Purpose: Run AlphaFold protein structure prediction on Google Cloud
Usage:
    python alphafold_pipeline.py --sequence MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSH
    python alphafold_pipeline.py --fasta protein.fasta --output gs://bucket/results

IMPORTANT: AlphaFold Database Options
=====================================
AlphaFold requires large reference databases (~2.5TB for full_dbs). For a POC:

1. USE reduced_dbs (default) - Only ~600GB, faster predictions, good accuracy
2. For production, consider:
   - Pre-staging databases in a regional GCS bucket
   - Using Google's public AlphaFold DB: gs://alphafold-public-datasets/
   - DeepMind's pre-computed structures: https://alphafold.ebi.ac.uk/

Cost Comparison:
  - reduced_dbs: ~30 min - 2 hrs per protein, ~$5-10/protein
  - full_dbs:    ~1 - 4 hrs per protein, ~$15-25/protein
=============================================================================
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from google.cloud import aiplatform
from google.cloud import storage


# Default configuration
PROJECT_ID = None  # Will use gcloud default
REGION = "us-central1"
STAGING_BUCKET = None  # Will be auto-generated
ALPHAFOLD_IMAGE = "gcr.io/cloud-lifesciences/alphafold:2.3.2"

# Public AlphaFold database locations (for reference)
PUBLIC_ALPHAFOLD_DBS = {
    "alphafold_structures": "gs://alphafold-public-datasets/",
    "uniref90": "gs://alphafold-public-datasets/uniref90/",
    "mgnify": "gs://alphafold-public-datasets/mgnify/",
}


def get_project_id() -> str:
    """Get the current GCP project ID from gcloud config."""
    result = subprocess.run(
        ["gcloud", "config", "get-value", "project"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def validate_sequence(sequence: str) -> bool:
    """Validate that a sequence contains only valid amino acids."""
    valid_aa = set("ACDEFGHIKLMNPQRSTVWY")
    sequence_upper = sequence.upper().replace(" ", "").replace("\n", "")
    return all(aa in valid_aa for aa in sequence_upper)


def create_fasta_file(
    sequence: str,
    name: str = "query",
    output_path: Optional[str] = None
) -> str:
    """Create a FASTA file from a sequence string."""
    if output_path is None:
        output_path = f"/tmp/{name}.fasta"
    
    fasta_content = f">{name}\n{sequence}\n"
    
    with open(output_path, "w") as f:
        f.write(fasta_content)
    
    return output_path


def upload_to_gcs(local_path: str, gcs_path: str) -> str:
    """Upload a local file to GCS."""
    client = storage.Client()
    
    # Parse GCS path
    if gcs_path.startswith("gs://"):
        gcs_path = gcs_path[5:]
    
    bucket_name = gcs_path.split("/")[0]
    blob_name = "/".join(gcs_path.split("/")[1:])
    
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(local_path)
    
    return f"gs://{bucket_name}/{blob_name}"


def create_alphafold_pipeline(
    fasta_gcs_path: str,
    output_gcs_path: str,
    project_id: str,
    region: str,
    max_template_date: str = "2022-01-01",
    model_preset: str = "monomer",
    db_preset: str = "reduced_dbs",
) -> dict:
    """Create the AlphaFold pipeline specification."""
    
    job_name = f"alphafold-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    
    # Define the pipeline as a Vertex AI custom job
    pipeline_spec = {
        "displayName": job_name,
        "jobSpec": {
            "workerPoolSpecs": [
                {
                    "machineSpec": {
                        "machineType": "a2-highgpu-1g",  # 1x A100 GPU
                        "acceleratorType": "NVIDIA_TESLA_A100",
                        "acceleratorCount": 1,
                    },
                    "replicaCount": 1,
                    "diskSpec": {
                        "bootDiskType": "pd-ssd",
                        "bootDiskSizeGb": 500,  # AlphaFold DBs are large
                    },
                    "containerSpec": {
                        "imageUri": ALPHAFOLD_IMAGE,
                        "command": ["/bin/bash", "-c"],
                        "args": [
                            f"""
                            python /app/alphafold/run_alphafold.py \
                                --fasta_paths={fasta_gcs_path} \
                                --output_dir={output_gcs_path} \
                                --max_template_date={max_template_date} \
                                --model_preset={model_preset} \
                                --db_preset={db_preset} \
                                --data_dir=/data/alphafold_dbs \
                                --use_gpu_relax=true
                            """
                        ],
                    },
                }
            ],
        },
    }
    
    return pipeline_spec


def run_alphafold_batch_job(
    fasta_gcs_path: str,
    output_gcs_path: str,
    project_id: str,
    region: str,
    model_preset: str = "monomer",
    db_preset: str = "reduced_dbs",
    dry_run: bool = False,
) -> Optional[str]:
    """
    Submit AlphaFold job using Cloud Batch (alternative to Vertex AI).
    This is more cost-effective for batch processing.
    """
    
    job_name = f"alphafold-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    
    batch_job = {
        "taskGroups": [{
            "taskSpec": {
                "runnables": [{
                    "container": {
                        "imageUri": ALPHAFOLD_IMAGE,
                        "commands": ["/bin/bash", "-c"],
                        "entrypoint": "",
                        "volumes": ["/data"],
                    },
                    "script": {
                        "text": f"""
#!/bin/bash
set -e

echo "Starting AlphaFold prediction..."
echo "Input: {fasta_gcs_path}"
echo "Output: {output_gcs_path}"

# Download input FASTA
gsutil cp {fasta_gcs_path} /tmp/input.fasta

# Run AlphaFold
python /app/alphafold/run_alphafold.py \
    --fasta_paths=/tmp/input.fasta \
    --output_dir=/tmp/output \
    --max_template_date=2022-01-01 \
    --model_preset={model_preset} \
    --db_preset={db_preset} \
    --use_gpu_relax=true

# Upload results
gsutil -m cp -r /tmp/output/* {output_gcs_path}/

echo "AlphaFold prediction complete!"
                        """
                    }
                }],
                "computeResource": {
                    "cpuMilli": 12000,  # 12 vCPUs
                    "memoryMib": 85000,  # 85 GB
                },
                "maxRetryCount": 1,
                "maxRunDuration": "43200s",  # 12 hours
            },
            "taskCount": 1,
            "parallelism": 1,
        }],
        "allocationPolicy": {
            "instances": [{
                "policy": {
                    "machineType": "a2-highgpu-1g",
                    "provisioningModel": "SPOT",  # Use Spot for cost savings
                },
                "installGpuDrivers": True,
            }],
            "location": {
                "allowedLocations": [f"zones/{region}-a", f"zones/{region}-b"],
            },
        },
        "logsPolicy": {
            "destination": "CLOUD_LOGGING",
        },
    }
    
    print("=" * 70)
    print("AlphaFold Batch Job Configuration")
    print("=" * 70)
    print(f"  Job Name:     {job_name}")
    print(f"  Input FASTA:  {fasta_gcs_path}")
    print(f"  Output:       {output_gcs_path}")
    print(f"  Model Preset: {model_preset}")
    print(f"  DB Preset:    {db_preset}")
    print(f"  GPU:          NVIDIA A100 (Spot)")
    print("=" * 70)
    
    if dry_run:
        print("\n[DRY RUN] Job specification:")
        print(json.dumps(batch_job, indent=2))
        return None
    
    # Submit job using gcloud
    job_json = json.dumps(batch_job)
    cmd = [
        "gcloud", "batch", "jobs", "submit", job_name,
        "--project", project_id,
        "--location", region,
        "--config", "-",
    ]
    
    print("\nSubmitting job to Cloud Batch...")
    result = subprocess.run(
        cmd,
        input=job_json,
        capture_output=True,
        text=True,
    )
    
    if result.returncode == 0:
        print(f"\n✓ Job submitted successfully: {job_name}")
        print(f"  Monitor at: https://console.cloud.google.com/batch/jobs?project={project_id}")
        return job_name
    else:
        print(f"\n✗ Job submission failed:")
        print(result.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Run AlphaFold protein structure prediction on Google Cloud",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Predict structure from sequence
  python alphafold_pipeline.py --sequence MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSH

  # Predict from FASTA file
  python alphafold_pipeline.py --fasta proteins.fasta --output gs://my-bucket/alphafold-results

  # Dry run to see configuration
  python alphafold_pipeline.py --sequence MVLSPADKTNVKAAWGKVG --dry-run
        """,
    )
    
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument(
        "--sequence", "-s",
        help="Amino acid sequence to predict",
    )
    input_group.add_argument(
        "--fasta", "-f",
        help="Path to FASTA file (local or GCS)",
    )
    
    parser.add_argument(
        "--output", "-o",
        help="GCS output path (default: auto-generated)",
    )
    parser.add_argument(
        "--project", "-p",
        help="GCP project ID (default: current gcloud project)",
    )
    parser.add_argument(
        "--region", "-r",
        default=REGION,
        help=f"GCP region (default: {REGION})",
    )
    parser.add_argument(
        "--model-preset",
        choices=["monomer", "monomer_casp14", "monomer_ptm", "multimer"],
        default="monomer",
        help="AlphaFold model preset (default: monomer)",
    )
    parser.add_argument(
        "--db-preset",
        choices=["reduced_dbs", "full_dbs"],
        default="reduced_dbs",
        help="Database preset (default: reduced_dbs for faster predictions)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print configuration without running",
    )
    
    args = parser.parse_args()
    
    # Resolve project ID
    project_id = args.project or get_project_id()
    print(f"Using project: {project_id}")
    
    # Handle input
    if args.sequence:
        if not validate_sequence(args.sequence):
            print("Error: Invalid amino acid sequence")
            sys.exit(1)
        
        # Create FASTA and upload
        local_fasta = create_fasta_file(args.sequence)
        staging_bucket = f"gs://{project_id}-staging-dev/alphafold-inputs"
        fasta_gcs_path = f"{staging_bucket}/query_{datetime.now().strftime('%Y%m%d_%H%M%S')}.fasta"
        
        if not args.dry_run:
            upload_to_gcs(local_fasta, fasta_gcs_path)
            print(f"Uploaded FASTA to: {fasta_gcs_path}")
    else:
        fasta_path = args.fasta
        if fasta_path.startswith("gs://"):
            fasta_gcs_path = fasta_path
        else:
            staging_bucket = f"gs://{project_id}-staging-dev/alphafold-inputs"
            fasta_gcs_path = f"{staging_bucket}/{Path(fasta_path).name}"
            if not args.dry_run:
                upload_to_gcs(fasta_path, fasta_gcs_path)
                print(f"Uploaded FASTA to: {fasta_gcs_path}")
    
    # Resolve output path
    output_gcs_path = args.output or f"gs://{project_id}-results-dev/alphafold/{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    # Run prediction
    job_name = run_alphafold_batch_job(
        fasta_gcs_path=fasta_gcs_path,
        output_gcs_path=output_gcs_path,
        project_id=project_id,
        region=args.region,
        model_preset=args.model_preset,
        db_preset=args.db_preset,
        dry_run=args.dry_run,
    )
    
    if job_name and not args.dry_run:
        print(f"\nResults will be available at:")
        print(f"  {output_gcs_path}/")


if __name__ == "__main__":
    main()
