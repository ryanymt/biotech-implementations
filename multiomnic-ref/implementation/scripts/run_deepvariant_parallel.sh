#!/bin/bash
# =============================================================================
# DeepVariant Parallel Runner Script (Chromosome Sharding)
# =============================================================================
# This script runs DeepVariant on a subset of chromosomes based on BATCH_TASK_INDEX
# Task 0: chr1-chr5
# Task 1: chr6-chr10  
# Task 2: chr11-chr15
# Task 3: chr16-chrY
# =============================================================================

set -euxo pipefail

# Arguments
BAM_PATH="${1}"
REFERENCE_PATH="${2}"
REFERENCE_FAI="${3}"
OUTPUT_DIR="${4}"
TASK_INDEX="${BATCH_TASK_INDEX:-0}"

# Define chromosome regions for each task
case $TASK_INDEX in
    0) REGIONS="chr1,chr2,chr3,chr4,chr5" ; REGION_NAME="chr1-5" ;;
    1) REGIONS="chr6,chr7,chr8,chr9,chr10" ; REGION_NAME="chr6-10" ;;
    2) REGIONS="chr11,chr12,chr13,chr14,chr15" ; REGION_NAME="chr11-15" ;;
    3) REGIONS="chr16,chr17,chr18,chr19,chr20,chr21,chr22,chrX,chrY" ; REGION_NAME="chr16-Y" ;;
    *) echo "Invalid TASK_INDEX: $TASK_INDEX" ; exit 1 ;;
esac

# Work directories
WORK_DIR="/tmp/deepvariant"
INPUT_DIR="${WORK_DIR}/input"
OUTPUT_LOCAL="${WORK_DIR}/output"
INTERMEDIATE_DIR="${WORK_DIR}/intermediate"

echo "=============================================="
echo "DeepVariant Parallel - Task ${TASK_INDEX}"
echo "=============================================="
echo "Regions:     ${REGIONS}"
echo "Region Name: ${REGION_NAME}"
echo "BAM:         ${BAM_PATH}"
echo "Reference:   ${REFERENCE_PATH}"
echo "Output Dir:  ${OUTPUT_DIR}"
echo "=============================================="

# Install gsutil and configure auth
echo "=== Installing gsutil ==="
pip install --quiet gsutil

echo "=== Configuring GCE auth ==="
mkdir -p ~/.config/gcloud
echo '[Credentials]' > ~/.boto
echo 'gs_service_client_id = default' >> ~/.boto
echo '[GoogleCompute]' >> ~/.boto
echo 'service_account = default' >> ~/.boto
export BOTO_CONFIG=~/.boto

# Create directories
mkdir -p "${INPUT_DIR}" "${OUTPUT_LOCAL}" "${INTERMEDIATE_DIR}"

# Download BAM
echo "=== Downloading BAM ==="
gsutil -m cp "${BAM_PATH}" "${INPUT_DIR}/sample.bam"

# Create BAM index
echo "=== Creating BAM index ==="
samtools index -@ 8 "${INPUT_DIR}/sample.bam"

# Download reference
echo "=== Downloading Reference ==="
gsutil -m cp "${REFERENCE_PATH}" "${INPUT_DIR}/reference.fasta"
gsutil -m cp "${REFERENCE_FAI}" "${INPUT_DIR}/reference.fasta.fai"

# Show disk space
echo "=== Disk space ==="
df -h /tmp
ls -la "${INPUT_DIR}/"

# Run DeepVariant for this region
echo "=== Running DeepVariant for ${REGION_NAME} ==="
/opt/deepvariant/bin/run_deepvariant \
    --model_type=WGS \
    --ref="${INPUT_DIR}/reference.fasta" \
    --reads="${INPUT_DIR}/sample.bam" \
    --regions="${REGIONS}" \
    --output_vcf="${OUTPUT_LOCAL}/sample_${REGION_NAME}.vcf.gz" \
    --output_gvcf="${OUTPUT_LOCAL}/sample_${REGION_NAME}.g.vcf.gz" \
    --num_shards=8 \
    --intermediate_results_dir="${INTERMEDIATE_DIR}"

# Upload outputs
echo "=== Uploading results ==="
ls -la "${OUTPUT_LOCAL}/"
gsutil cp "${OUTPUT_LOCAL}/sample_${REGION_NAME}.vcf.gz" "${OUTPUT_DIR}/shards/sample_${REGION_NAME}.vcf.gz"
gsutil cp "${OUTPUT_LOCAL}/sample_${REGION_NAME}.g.vcf.gz" "${OUTPUT_DIR}/shards/sample_${REGION_NAME}.g.vcf.gz"

echo "=============================================="
echo "Task ${TASK_INDEX} (${REGION_NAME}) Complete!"
echo "=============================================="
