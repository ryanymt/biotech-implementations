#!/bin/bash
# =============================================================================
# DeepVariant Runner Script (for GCS-mounted volumes)
# =============================================================================
# This script runs DeepVariant variant calling on a BAM file
# Uses mounted GCS paths directly (no gcloud storage cp needed)
# =============================================================================

set -euxo pipefail  # Exit on error, print commands, fail on pipe errors

# Arguments (now expecting local mounted paths)
BAM_PATH="${1}"
REFERENCE_PATH="${2}"
OUTPUT_VCF="${3}"
MODEL_TYPE="${4:-WGS}"
NUM_SHARDS="${5:-32}"

# Derived paths
OUTPUT_GVCF="${OUTPUT_VCF%.vcf.gz}.g.vcf.gz"
WORK_DIR="/tmp/deepvariant"
INPUT_DIR="${WORK_DIR}/input"
OUTPUT_DIR="${WORK_DIR}/output"
INTERMEDIATE_DIR="${WORK_DIR}/intermediate"

echo "=============================================="
echo "DeepVariant Variant Calling"
echo "=============================================="
echo "BAM:        ${BAM_PATH}"
echo "Reference:  ${REFERENCE_PATH}"
echo "Output VCF: ${OUTPUT_VCF}"
echo "Output gVCF: ${OUTPUT_GVCF}"
echo "Model Type: ${MODEL_TYPE}"
echo "Num Shards: ${NUM_SHARDS}"
echo "=============================================="

# Create working directories
echo "Creating working directories..."
mkdir -p "${INPUT_DIR}" "${OUTPUT_DIR}" "${INTERMEDIATE_DIR}"

# Copy BAM to local disk (faster I/O)
echo "Copying BAM to local disk..."
time cp "${BAM_PATH}" "${INPUT_DIR}/sample.bam"

# Create BAM index if needed
echo "Creating/copying BAM index..."
if [ -f "${BAM_PATH}.bai" ]; then
    cp "${BAM_PATH}.bai" "${INPUT_DIR}/sample.bam.bai"
else
    echo "Creating BAM index with samtools..."
    samtools index -@ "${NUM_SHARDS}" "${INPUT_DIR}/sample.bam"
fi

# Copy reference to local disk
echo "Copying reference genome to local disk..."
time cp "${REFERENCE_PATH}" "${INPUT_DIR}/reference.fasta"

# Create reference index if needed
echo "Creating/copying reference index..."
if [ -f "${REFERENCE_PATH}.fai" ]; then
    cp "${REFERENCE_PATH}.fai" "${INPUT_DIR}/reference.fasta.fai"
else
    echo "Creating reference index with samtools..."
    samtools faidx "${INPUT_DIR}/reference.fasta"
fi

# Check disk space
echo "Checking disk space..."
df -h "${WORK_DIR}"

# List input files
echo "Input files:"
ls -la "${INPUT_DIR}"

# Run DeepVariant
echo "=============================================="
echo "Starting DeepVariant..."
echo "=============================================="
time /opt/deepvariant/bin/run_deepvariant \
    --model_type="${MODEL_TYPE}" \
    --ref="${INPUT_DIR}/reference.fasta" \
    --reads="${INPUT_DIR}/sample.bam" \
    --output_vcf="${OUTPUT_DIR}/sample.vcf.gz" \
    --output_gvcf="${OUTPUT_DIR}/sample.g.vcf.gz" \
    --num_shards="${NUM_SHARDS}" \
    --intermediate_results_dir="${INTERMEDIATE_DIR}"

# Create output directory if needed
OUTPUT_DIR_PATH=$(dirname "${OUTPUT_VCF}")
mkdir -p "${OUTPUT_DIR_PATH}"

# Copy outputs to mounted output path
echo "=============================================="
echo "Copying results to output..."
echo "=============================================="
echo "Output files:"
ls -la "${OUTPUT_DIR}"

cp "${OUTPUT_DIR}/sample.vcf.gz" "${OUTPUT_VCF}"
cp "${OUTPUT_DIR}/sample.vcf.gz.tbi" "${OUTPUT_VCF}.tbi" 2>/dev/null || true
cp "${OUTPUT_DIR}/sample.g.vcf.gz" "${OUTPUT_GVCF}"

echo "=============================================="
echo "DeepVariant complete!"
echo "VCF:  ${OUTPUT_VCF}"
echo "gVCF: ${OUTPUT_GVCF}"
echo "=============================================="
