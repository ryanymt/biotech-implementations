#!/usr/bin/env python3
"""
=============================================================================
Nextflow Pipeline Runner CLI
=============================================================================
Purpose: Python CLI wrapper for launching Nextflow pipelines on Cloud Batch
Usage:
    python run_pipeline.py qc --sample HG00119
    python run_pipeline.py variant-calling --bam gs://bucket/sample.bam
=============================================================================
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


# Configuration
SCRIPT_DIR = Path(__file__).parent
PIPELINES_DIR = SCRIPT_DIR.parent / "pipelines"
DEFAULT_PROFILE = "gcp"


def get_project_id() -> str:
    """Get current GCP project ID."""
    result = subprocess.run(
        ["gcloud", "config", "get-value", "project"],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def run_nextflow(
    workflow: str,
    params: dict,
    profile: str = DEFAULT_PROFILE,
    resume: bool = False,
    work_dir: Optional[str] = None,
    dry_run: bool = False,
) -> int:
    """Run a Nextflow pipeline."""
    
    project_id = get_project_id()
    
    # Build command
    cmd = [
        "nextflow", "run",
        str(PIPELINES_DIR / "main.nf"),
        "-profile", profile,
        "-entry", workflow.upper().replace("-", "_"),
    ]
    
    # Add parameters
    for key, value in params.items():
        if value is not None:
            cmd.extend([f"--{key}", str(value)])
    
    # Add options
    if resume:
        cmd.append("-resume")
    
    if work_dir:
        cmd.extend(["-work-dir", work_dir])
    else:
        cmd.extend(["-work-dir", f"gs://{project_id}-multiomics-staging-dev/work"])
    
    # Add timestamp to output
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    if "outdir" not in params:
        cmd.extend(["--outdir", f"gs://{project_id}-multiomics-results-dev/{workflow}/{timestamp}"])
    
    print("=" * 70)
    print(f"Running Nextflow Pipeline: {workflow}")
    print("=" * 70)
    print(f"Command: {' '.join(cmd)}")
    print("=" * 70)
    
    if dry_run:
        print("[DRY RUN] Command not executed.")
        return 0
    
    # Execute
    os.chdir(PIPELINES_DIR)
    result = subprocess.run(cmd)
    return result.returncode


def cmd_qc(args):
    """Run QC pipeline."""
    params = {
        "sample_id": args.sample,
        "input_bam": args.bam,
        "outdir": args.output,
    }
    return run_nextflow(
        workflow="qc",
        params={k: v for k, v in params.items() if v is not None},
        profile=args.profile,
        resume=args.resume,
        dry_run=args.dry_run,
    )


def cmd_variant_calling(args):
    """Run variant calling pipeline."""
    params = {
        "sample_id": args.sample,
        "input_bam": args.bam,
        "reference": args.reference,
        "use_deepvariant": not args.use_gatk,
        "outdir": args.output,
    }
    return run_nextflow(
        workflow="variant_calling",
        params={k: v for k, v in params.items() if v is not None},
        profile=args.profile,
        resume=args.resume,
        dry_run=args.dry_run,
    )


def cmd_full(args):
    """Run full pipeline (QC + variant calling)."""
    params = {
        "sample_id": args.sample,
        "input_bam": args.bam,
        "reference": args.reference,
        "skip_qc": False,
        "run_variant_calling": True,
        "outdir": args.output,
    }
    return run_nextflow(
        workflow="main",
        params={k: v for k, v in params.items() if v is not None},
        profile=args.profile,
        resume=args.resume,
        dry_run=args.dry_run,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Run genomic analysis pipelines on Google Cloud",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    
    # Global options
    parser.add_argument(
        "--profile", "-p",
        default=DEFAULT_PROFILE,
        choices=["local", "gcp", "test"],
        help=f"Nextflow profile (default: {DEFAULT_PROFILE})",
    )
    parser.add_argument(
        "--resume", "-r",
        action="store_true",
        help="Resume previous run",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print command without executing",
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Available pipelines")
    
    # QC subcommand
    qc_parser = subparsers.add_parser("qc", help="Run quality control pipeline")
    qc_parser.add_argument("--sample", "-s", required=True, help="Sample ID")
    qc_parser.add_argument("--bam", "-b", help="Input BAM file (GCS path)")
    qc_parser.add_argument("--output", "-o", help="Output directory (GCS path)")
    qc_parser.set_defaults(func=cmd_qc)
    
    # Variant calling subcommand
    vc_parser = subparsers.add_parser("variant-calling", help="Run variant calling pipeline")
    vc_parser.add_argument("--sample", "-s", required=True, help="Sample ID")
    vc_parser.add_argument("--bam", "-b", required=True, help="Input BAM file (GCS path)")
    vc_parser.add_argument("--reference", help="Reference genome (GCS path)")
    vc_parser.add_argument("--use-gatk", action="store_true", help="Use GATK instead of DeepVariant")
    vc_parser.add_argument("--output", "-o", help="Output directory (GCS path)")
    vc_parser.set_defaults(func=cmd_variant_calling)
    
    # Full pipeline subcommand
    full_parser = subparsers.add_parser("full", help="Run complete pipeline (QC + variant calling)")
    full_parser.add_argument("--sample", "-s", required=True, help="Sample ID")
    full_parser.add_argument("--bam", "-b", required=True, help="Input BAM file (GCS path)")
    full_parser.add_argument("--reference", help="Reference genome (GCS path)")
    full_parser.add_argument("--output", "-o", help="Output directory (GCS path)")
    full_parser.set_defaults(func=cmd_full)
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
