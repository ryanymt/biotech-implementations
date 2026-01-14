#!/usr/bin/env python3
"""
=============================================================================
DeepVariant Batch Job Launcher
=============================================================================
Purpose: Run DeepVariant variant calling on Google Cloud Batch
Usage:
    python deepvariant_batch.py --bam gs://bucket/sample.bam --reference gs://bucket/ref.fasta
=============================================================================
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime
from typing import Optional


# Default configuration
DEEPVARIANT_VERSION = "1.5.0"
DEEPVARIANT_IMAGE = f"google/deepvariant:{DEEPVARIANT_VERSION}-gpu"
MODEL_TYPE = "WGS"  # or WES, PACBIO, ONT_R104, HYBRID_PACBIO_ILLUMINA


def get_project_id() -> str:
    """Get the current GCP project ID from gcloud config."""
    result = subprocess.run(
        ["gcloud", "config", "get-value", "project"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def create_deepvariant_batch_job(
    bam_path: str,
    reference_path: str,
    output_vcf_path: str,
    output_gvcf_path: str,
    project_id: str,
    region: str,
    model_type: str = MODEL_TYPE,
    num_shards: int = 16,
    use_spot: bool = True,
) -> dict:
    """Create Cloud Batch job specification for DeepVariant."""
    
    job_name = f"deepvariant-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    
    # DeepVariant command
    dv_command = f"""
#!/bin/bash
set -e

echo "=============================================="
echo "DeepVariant Variant Calling"
echo "=============================================="
echo "BAM:       {bam_path}"
echo "Reference: {reference_path}"
echo "Output:    {output_vcf_path}"
echo "Model:     {model_type}"
echo "=============================================="

# Install gsutil (not in DeepVariant container by default)
echo "Installing gsutil..."
apt-get update -qq && apt-get install -qq -y curl python3-pip > /dev/null 2>&1 || true
pip3 install -q --no-cache-dir gsutil || pip install -q --no-cache-dir gsutil || true

# Create working directories
mkdir -p /tmp/deepvariant/input
mkdir -p /tmp/deepvariant/output
mkdir -p /tmp/deepvariant/intermediate

# Download inputs using gcloud storage (fallback to gsutil)
echo "Downloading BAM file..."
gcloud storage cp {bam_path} /tmp/deepvariant/input/sample.bam 2>/dev/null || gsutil cp {bam_path} /tmp/deepvariant/input/sample.bam
echo "Downloading BAM index..."
gcloud storage cp {bam_path}.bai /tmp/deepvariant/input/sample.bam.bai 2>/dev/null || samtools index /tmp/deepvariant/input/sample.bam || true

echo "Downloading reference genome..."
gcloud storage cp {reference_path} /tmp/deepvariant/input/reference.fasta 2>/dev/null || gsutil cp {reference_path} /tmp/deepvariant/input/reference.fasta
gcloud storage cp {reference_path}.fai /tmp/deepvariant/input/reference.fasta.fai 2>/dev/null || samtools faidx /tmp/deepvariant/input/reference.fasta || true

# Run DeepVariant
echo "Running DeepVariant..."
/opt/deepvariant/bin/run_deepvariant \\
    --model_type={model_type} \\
    --ref=/tmp/deepvariant/input/reference.fasta \\
    --reads=/tmp/deepvariant/input/sample.bam \\
    --output_vcf=/tmp/deepvariant/output/sample.vcf.gz \\
    --output_gvcf=/tmp/deepvariant/output/sample.g.vcf.gz \\
    --num_shards={num_shards} \\
    --intermediate_results_dir=/tmp/deepvariant/intermediate

# Upload outputs
echo "Uploading results..."
gcloud storage cp /tmp/deepvariant/output/sample.vcf.gz {output_vcf_path} 2>/dev/null || gsutil cp /tmp/deepvariant/output/sample.vcf.gz {output_vcf_path}
gcloud storage cp /tmp/deepvariant/output/sample.vcf.gz.tbi {output_vcf_path}.tbi 2>/dev/null || gsutil cp /tmp/deepvariant/output/sample.vcf.gz.tbi {output_vcf_path}.tbi
gcloud storage cp /tmp/deepvariant/output/sample.g.vcf.gz {output_gvcf_path} 2>/dev/null || gsutil cp /tmp/deepvariant/output/sample.g.vcf.gz {output_gvcf_path}

echo "=============================================="
echo "DeepVariant complete!"
echo "VCF:  {output_vcf_path}"
echo "gVCF: {output_gvcf_path}"
echo "=============================================="
"""
    
    batch_job = {
        "taskGroups": [{
            "taskSpec": {
                "runnables": [{
                    "container": {
                        "imageUri": DEEPVARIANT_IMAGE,
                        "entrypoint": "/bin/bash",
                        "commands": ["-c", dv_command],
                    },
                }],
                "computeResource": {
                    "cpuMilli": 32000,  # 32 vCPUs
                    "memoryMib": 128000,  # 128 GB
                },
                "maxRetryCount": 1,
                "maxRunDuration": "14400s",  # 4 hours
            },
            "taskCount": 1,
            "parallelism": 1,
        }],
        "allocationPolicy": {
            "instances": [{
                "policy": {
                    "machineType": "n1-standard-32",
                    "provisioningModel": "SPOT" if use_spot else "STANDARD",
                    "accelerators": [{
                        "type": "nvidia-tesla-t4",
                        "count": 1,
                    }],
                    "bootDisk": {
                        "sizeGb": 100,  # 100GB for WGS data
                        "type": "pd-ssd",
                    },
                },
                "installGpuDrivers": True,
            }],
            "location": {
                "allowedLocations": [f"zones/{region}-a", f"zones/{region}-b", f"zones/{region}-c"],
            },
            "network": {
                "networkInterfaces": [{
                    "network": f"projects/{project_id}/global/networks/multiomics-vpc",
                    "subnetwork": f"projects/{project_id}/regions/{region}/subnetworks/multiomics-vpc",
                }],
            },
        },
        "logsPolicy": {
            "destination": "CLOUD_LOGGING",
        },
    }
    
    return job_name, batch_job


def submit_batch_job(
    job_name: str,
    job_spec: dict,
    project_id: str,
    region: str,
    dry_run: bool = False,
) -> Optional[str]:
    """Submit a Cloud Batch job."""
    
    if dry_run:
        print("\n[DRY RUN] Job specification:")
        print(json.dumps(job_spec, indent=2))
        return None
    
    job_json = json.dumps(job_spec)
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
        description="Run DeepVariant variant calling on Google Cloud Batch",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage with WGS data
  python deepvariant_batch.py \\
      --bam gs://my-bucket/sample.bam \\
      --reference gs://genomics-public-data/resources/broad/hg38/v0/Homo_sapiens_assembly38.fasta \\
      --output gs://my-bucket/results/sample.vcf.gz

  # WES (exome) data
  python deepvariant_batch.py \\
      --bam gs://my-bucket/exome.bam \\
      --reference gs://bucket/ref.fasta \\
      --output gs://my-bucket/exome.vcf.gz \\
      --model-type WES

  # Use standard VMs instead of Spot
  python deepvariant_batch.py --bam gs://bucket/sample.bam --reference gs://bucket/ref.fasta --no-spot
        """,
    )
    
    parser.add_argument(
        "--bam", "-b",
        required=True,
        help="GCS path to input BAM file",
    )
    parser.add_argument(
        "--reference", "-r",
        required=True,
        help="GCS path to reference FASTA",
    )
    parser.add_argument(
        "--output", "-o",
        help="GCS path for output VCF (default: auto-generated)",
    )
    parser.add_argument(
        "--project", "-p",
        help="GCP project ID (default: current gcloud project)",
    )
    parser.add_argument(
        "--region",
        default="us-central1",
        help="GCP region (default: us-central1)",
    )
    parser.add_argument(
        "--model-type",
        choices=["WGS", "WES", "PACBIO", "ONT_R104", "HYBRID_PACBIO_ILLUMINA"],
        default="WGS",
        help="DeepVariant model type (default: WGS)",
    )
    parser.add_argument(
        "--num-shards",
        type=int,
        default=16,
        help="Number of shards for parallel processing (default: 16)",
    )
    parser.add_argument(
        "--no-spot",
        action="store_true",
        help="Use standard VMs instead of Spot (more expensive but reliable)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print job spec without submitting",
    )
    
    args = parser.parse_args()
    
    # Resolve project ID
    project_id = args.project or get_project_id()
    print(f"Using project: {project_id}")
    
    # Generate output paths
    if args.output:
        output_vcf = args.output
        output_gvcf = args.output.replace(".vcf.gz", ".g.vcf.gz")
    else:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_vcf = f"gs://{project_id}-multiomics-results-dev/deepvariant/{timestamp}/sample.vcf.gz"
        output_gvcf = f"gs://{project_id}-multiomics-results-dev/deepvariant/{timestamp}/sample.g.vcf.gz"
    
    print("=" * 70)
    print("DeepVariant Batch Job Configuration")
    print("=" * 70)
    print(f"  BAM Input:    {args.bam}")
    print(f"  Reference:    {args.reference}")
    print(f"  Output VCF:   {output_vcf}")
    print(f"  Output gVCF:  {output_gvcf}")
    print(f"  Model Type:   {args.model_type}")
    print(f"  Num Shards:   {args.num_shards}")
    print(f"  Use Spot:     {not args.no_spot}")
    print("=" * 70)
    
    # Create and submit job
    job_name, job_spec = create_deepvariant_batch_job(
        bam_path=args.bam,
        reference_path=args.reference,
        output_vcf_path=output_vcf,
        output_gvcf_path=output_gvcf,
        project_id=project_id,
        region=args.region,
        model_type=args.model_type,
        num_shards=args.num_shards,
        use_spot=not args.no_spot,
    )
    
    result = submit_batch_job(
        job_name=job_name,
        job_spec=job_spec,
        project_id=project_id,
        region=args.region,
        dry_run=args.dry_run,
    )
    
    if result:
        print(f"\nResults will be available at:")
        print(f"  VCF:  {output_vcf}")
        print(f"  gVCF: {output_gvcf}")


if __name__ == "__main__":
    main()
