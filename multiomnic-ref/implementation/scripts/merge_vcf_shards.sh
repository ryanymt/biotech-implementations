#!/bin/bash
# =============================================================================
# DeepVariant Merge Script
# =============================================================================
# Merges per-chromosome VCF shards into a single VCF
# =============================================================================

set -euxo pipefail

OUTPUT_DIR="${1}"

echo "=== Installing tools ==="
pip install --quiet gsutil

echo "=== Configuring GCE auth ==="
echo '[Credentials]' > ~/.boto
echo 'gs_service_client_id = default' >> ~/.boto
echo '[GoogleCompute]' >> ~/.boto
echo 'service_account = default' >> ~/.boto
export BOTO_CONFIG=~/.boto

WORK_DIR="/tmp/merge"
mkdir -p "${WORK_DIR}"

echo "=== Downloading VCF shards ==="
gsutil -m cp "${OUTPUT_DIR}/shards/*.vcf.gz" "${WORK_DIR}/"

echo "=== Listing shards ==="
ls -la "${WORK_DIR}/"

echo "=== Merging VCFs ==="
# Use bcftools to merge (should be in DeepVariant container)
# Order matters: chr1-5, chr6-10, chr11-15, chr16-Y
bcftools concat \
    "${WORK_DIR}/sample_chr1-5.vcf.gz" \
    "${WORK_DIR}/sample_chr6-10.vcf.gz" \
    "${WORK_DIR}/sample_chr11-15.vcf.gz" \
    "${WORK_DIR}/sample_chr16-Y.vcf.gz" \
    -O z -o "${WORK_DIR}/merged.vcf.gz"

# Index the merged VCF
bcftools index -t "${WORK_DIR}/merged.vcf.gz"

echo "=== Uploading merged VCF ==="
gsutil cp "${WORK_DIR}/merged.vcf.gz" "${OUTPUT_DIR}/HG00119_final.vcf.gz"
gsutil cp "${WORK_DIR}/merged.vcf.gz.tbi" "${OUTPUT_DIR}/HG00119_final.vcf.gz.tbi"

echo "=== Merge Complete ==="
echo "Output: ${OUTPUT_DIR}/HG00119_final.vcf.gz"
