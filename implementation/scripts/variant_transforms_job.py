#!/usr/bin/env python3
"""
=============================================================================
Variant Transforms Job Launcher
=============================================================================
Purpose: Launch Google Cloud Variant Transforms to ingest VCF files into BigQuery
Usage:
    python variant_transforms_job.py --vcf gs://bucket/sample.vcf.gz --dataset genomics_warehouse
=============================================================================
"""

import argparse
import subprocess
import sys
from datetime import datetime
from typing import Optional


# Default configuration
DEFAULTS = {
    "project": None,  # Will use gcloud default
    "region": "us-central1",
    "dataset": "genomics_warehouse",
    "table": "variants",
    "temp_location": None,  # Will be auto-generated
    "runner": "DataflowRunner",
    "machine_type": "n1-standard-16",
    "max_workers": 50,
}

# Variant Transforms Docker image
VT_IMAGE = "gcr.io/cloud-lifesciences/gcp-variant-transforms"


def get_project_id() -> str:
    """Get the current GCP project ID from gcloud config."""
    result = subprocess.run(
        ["gcloud", "config", "get-value", "project"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def build_variant_transforms_command(
    vcf_path: str,
    project: str,
    dataset: str,
    table: str,
    region: str,
    temp_location: str,
    machine_type: str,
    max_workers: int,
    append: bool = False,
    representative_header: Optional[str] = None,
) -> list[str]:
    """Build the Variant Transforms command."""
    
    # Base command
    cmd = [
        "docker", "run", "-v", "/tmp:/tmp",
        VT_IMAGE,
        "/opt/gcp_variant_transforms/bin/vcf_to_bq",
    ]
    
    # Required arguments
    cmd.extend([
        "--project", project,
        "--input_pattern", vcf_path,
        "--output_table", f"{project}:{dataset}.{table}",
        "--temp_location", temp_location,
        "--job_name", f"vcf-to-bq-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
        "--runner", "DataflowRunner",
        "--region", region,
    ])
    
    # Performance tuning
    cmd.extend([
        "--worker_machine_type", machine_type,
        "--max_num_workers", str(max_workers),
        "--worker_disk_type", "compute.googleapis.com/projects//zones//diskTypes/pd-ssd",
    ])
    
    # Schema options
    cmd.extend([
        "--sample_name_encoding", "without_sample_name",  # For single-sample VCFs
    ])
    
    if append:
        cmd.append("--append")
    
    if representative_header:
        cmd.extend(["--representative_header_file", representative_header])
    
    return cmd


def run_variant_transforms(
    vcf_path: str,
    project: Optional[str] = None,
    dataset: str = DEFAULTS["dataset"],
    table: str = DEFAULTS["table"],
    region: str = DEFAULTS["region"],
    machine_type: str = DEFAULTS["machine_type"],
    max_workers: int = DEFAULTS["max_workers"],
    append: bool = False,
    dry_run: bool = False,
) -> int:
    """Run Variant Transforms to ingest VCF into BigQuery."""
    
    # Resolve project ID
    if not project:
        project = get_project_id()
        print(f"Using project: {project}")
    
    # Generate temp location
    temp_location = f"gs://{project}-multiomics-staging-dev/variant-transforms-temp"
    
    print("=" * 70)
    print("Variant Transforms Job Configuration")
    print("=" * 70)
    print(f"  VCF Input:    {vcf_path}")
    print(f"  Project:      {project}")
    print(f"  Dataset:      {dataset}")
    print(f"  Table:        {table}")
    print(f"  Region:       {region}")
    print(f"  Machine Type: {machine_type}")
    print(f"  Max Workers:  {max_workers}")
    print(f"  Append Mode:  {append}")
    print("=" * 70)
    
    # Build command
    cmd = build_variant_transforms_command(
        vcf_path=vcf_path,
        project=project,
        dataset=dataset,
        table=table,
        region=region,
        temp_location=temp_location,
        machine_type=machine_type,
        max_workers=max_workers,
        append=append,
    )
    
    print("\nCommand:")
    print(" ".join(cmd))
    print()
    
    if dry_run:
        print("[DRY RUN] Command not executed.")
        return 0
    
    # Execute
    print("Starting Variant Transforms job...")
    print("(This may take several minutes depending on VCF size)")
    print()
    
    try:
        result = subprocess.run(cmd, check=True)
        print("\n✓ Variant Transforms job completed successfully!")
        print(f"  Data available at: {project}.{dataset}.{table}")
        return 0
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Variant Transforms job failed with exit code: {e.returncode}")
        return e.returncode


def main():
    parser = argparse.ArgumentParser(
        description="Launch Variant Transforms to ingest VCF files into BigQuery",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Ingest a single VCF from GCS
  python variant_transforms_job.py --vcf gs://genomics-public-data/platinum-genomes/vcf/NA12877_S1.genome.vcf.gz

  # Ingest multiple VCFs with a glob pattern
  python variant_transforms_job.py --vcf "gs://my-bucket/vcfs/*.vcf.gz" --append

  # Custom dataset and table
  python variant_transforms_job.py --vcf gs://bucket/sample.vcf.gz --dataset my_dataset --table my_variants
        """,
    )
    
    parser.add_argument(
        "--vcf", "-i",
        required=True,
        help="GCS path to VCF file(s). Supports glob patterns.",
    )
    parser.add_argument(
        "--project", "-p",
        help="GCP project ID (default: current gcloud project)",
    )
    parser.add_argument(
        "--dataset", "-d",
        default=DEFAULTS["dataset"],
        help=f"BigQuery dataset name (default: {DEFAULTS['dataset']})",
    )
    parser.add_argument(
        "--table", "-t",
        default=DEFAULTS["table"],
        help=f"BigQuery table name (default: {DEFAULTS['table']})",
    )
    parser.add_argument(
        "--region", "-r",
        default=DEFAULTS["region"],
        help=f"GCP region for Dataflow (default: {DEFAULTS['region']})",
    )
    parser.add_argument(
        "--machine-type",
        default=DEFAULTS["machine_type"],
        help=f"Worker machine type (default: {DEFAULTS['machine_type']})",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=DEFAULTS["max_workers"],
        help=f"Maximum number of workers (default: {DEFAULTS['max_workers']})",
    )
    parser.add_argument(
        "--append",
        action="store_true",
        help="Append to existing table instead of creating new",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print command without executing",
    )
    
    args = parser.parse_args()
    
    exit_code = run_variant_transforms(
        vcf_path=args.vcf,
        project=args.project,
        dataset=args.dataset,
        table=args.table,
        region=args.region,
        machine_type=args.machine_type,
        max_workers=args.max_workers,
        append=args.append,
        dry_run=args.dry_run,
    )
    
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
