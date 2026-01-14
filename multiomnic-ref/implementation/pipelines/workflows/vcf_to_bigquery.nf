#!/usr/bin/env nextflow

/*
 * =============================================================================
 * VCF to BigQuery Pipeline
 * =============================================================================
 * Purpose: Load variant data from VCF files into BigQuery for analysis
 * 
 * Approach: Uses bcftools to extract key variant fields, then bq load
 * This is the "Option A" approach - simple and reliable
 * =============================================================================
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Process: VCF_TO_TSV
// ---------------------------------------------------------------------------
// Extract variant data from VCF to TSV format using bcftools

process VCF_TO_TSV {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/bcftools:1.17--h3cc50cf_1'
    
    publishDir "${params.outdir}/bigquery", mode: 'copy'
    
    input:
    tuple val(sample_id), path(vcf)
    
    output:
    tuple val(sample_id), path("${sample_id}_variants.tsv"), emit: tsv
    
    script:
    """
    # Extract key fields from VCF
    echo -e "sample_id\tchromosome\tposition\tid\tref\talt\tquality\tfilter" > ${sample_id}_variants.tsv
    
    bcftools query -f '${sample_id}\t%CHROM\t%POS\t%ID\t%REF\t%ALT\t%QUAL\t%FILTER\n' ${vcf} >> ${sample_id}_variants.tsv
    
    # Report row count
    echo "Extracted \$(wc -l < ${sample_id}_variants.tsv) variants for ${sample_id}"
    """
}

// ---------------------------------------------------------------------------
// Process: UPLOAD_TO_GCS
// ---------------------------------------------------------------------------
// Upload TSV to GCS for BigQuery loading

process UPLOAD_TO_GCS {
    tag "${sample_id}"
    label 'process_low'
    
    container 'google/cloud-sdk:slim'
    
    input:
    tuple val(sample_id), path(tsv)
    
    output:
    tuple val(sample_id), val(gcs_path), emit: gcs_location
    
    script:
    gcs_path = "${params.gcs_results_bucket}/bigquery/${sample_id}_variants.tsv"
    """
    gsutil cp ${tsv} ${gcs_path}
    echo "Uploaded to: ${gcs_path}"
    """
}

// ---------------------------------------------------------------------------
// Process: LOAD_TO_BIGQUERY
// ---------------------------------------------------------------------------
// Load TSV data into BigQuery table

process LOAD_TO_BIGQUERY {
    tag "${sample_id}"
    label 'process_low'
    
    container 'google/cloud-sdk:slim'
    
    input:
    tuple val(sample_id), val(gcs_path)
    
    output:
    tuple val(sample_id), val(table_name), emit: table
    
    script:
    table_name = "${params.bq_dataset}.${params.bq_table}"
    """
    # Load data into BigQuery (append mode)
    bq load \
        --source_format=CSV \
        --field_delimiter=tab \
        --skip_leading_rows=1 \
        --autodetect \
        ${table_name} \
        ${gcs_path}
    
    echo "Loaded ${sample_id} data into ${table_name}"
    """
}

// ---------------------------------------------------------------------------
// Workflow: VCF_TO_BIGQUERY
// ---------------------------------------------------------------------------

workflow VCF_TO_BIGQUERY {
    take:
    ch_vcf  // tuple(sample_id, vcf_path)
    
    main:
    // Extract variants to TSV
    VCF_TO_TSV(ch_vcf)
    
    // Upload to GCS
    UPLOAD_TO_GCS(VCF_TO_TSV.out.tsv)
    
    // Load to BigQuery
    LOAD_TO_BIGQUERY(UPLOAD_TO_GCS.out.gcs_location)
    
    emit:
    tsv   = VCF_TO_TSV.out.tsv
    table = LOAD_TO_BIGQUERY.out.table
}
