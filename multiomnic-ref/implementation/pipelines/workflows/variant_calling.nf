#!/usr/bin/env nextflow

/*
 * =============================================================================
 * Variant Calling Pipeline
 * =============================================================================
 * Purpose: Call genetic variants from BAM files using DeepVariant or GATK
 * 
 * Inputs:
 *   - ch_bam: tuple(sample_id, bam, bai)
 *   - ch_reference: path to reference FASTA
 * 
 * Outputs:
 *   - vcf: Called variants in VCF format
 *   - gvcf: Genomic VCF for multi-sample analysis
 * =============================================================================
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Process: DEEPVARIANT_CALL_VARIANTS
// ---------------------------------------------------------------------------
// GPU-accelerated variant calling with DeepVariant

process DEEPVARIANT_CALL_VARIANTS {
    tag "${sample_id}"
    label 'process_gpu'
    
    container 'google/deepvariant:1.5.0-gpu'
    
    publishDir "${params.outdir}/variants/deepvariant", mode: 'copy'
    
    input:
    tuple val(sample_id), path(bam), path(bai)
    path reference
    
    output:
    tuple val(sample_id), path("${sample_id}.vcf.gz"), path("${sample_id}.vcf.gz.tbi"), emit: vcf
    tuple val(sample_id), path("${sample_id}.g.vcf.gz"), emit: gvcf
    path "${sample_id}.visual_report.html", emit: report
    
    script:
    """
    # Index reference if needed
    if [ ! -f ${reference}.fai ]; then
        samtools faidx ${reference}
    fi
    
    # Run DeepVariant
    /opt/deepvariant/bin/run_deepvariant \\
        --model_type=WGS \\
        --ref=${reference} \\
        --reads=${bam} \\
        --output_vcf=${sample_id}.vcf.gz \\
        --output_gvcf=${sample_id}.g.vcf.gz \\
        --num_shards=${task.cpus} \\
        --intermediate_results_dir=./tmp \\
        --logging_dir=./logs
    
    # Generate visual report
    echo "<html><body><h1>DeepVariant Report: ${sample_id}</h1></body></html>" > ${sample_id}.visual_report.html
    """
}

// ---------------------------------------------------------------------------
// Process: GATK_HAPLOTYPE_CALLER
// ---------------------------------------------------------------------------
// Traditional GATK-based variant calling (alternative to DeepVariant)

process GATK_HAPLOTYPE_CALLER {
    tag "${sample_id}"
    label 'process_high'
    
    container 'broadinstitute/gatk:4.4.0.0'
    
    publishDir "${params.outdir}/variants/gatk", mode: 'copy'
    
    input:
    tuple val(sample_id), path(bam), path(bai)
    path reference
    
    output:
    tuple val(sample_id), path("${sample_id}.gatk.vcf.gz"), path("${sample_id}.gatk.vcf.gz.tbi"), emit: vcf
    tuple val(sample_id), path("${sample_id}.gatk.g.vcf.gz"), emit: gvcf
    
    script:
    """
    # Index reference if needed
    if [ ! -f ${reference}.fai ]; then
        samtools faidx ${reference}
    fi
    
    # Create sequence dictionary
    if [ ! -f ${reference%.fasta}.dict ]; then
        gatk CreateSequenceDictionary -R ${reference}
    fi
    
    # Run HaplotypeCaller
    gatk HaplotypeCaller \\
        -R ${reference} \\
        -I ${bam} \\
        -O ${sample_id}.gatk.vcf.gz \\
        -ERC GVCF \\
        --native-pair-hmm-threads ${task.cpus}
    
    # Index VCF
    gatk IndexFeatureFile -I ${sample_id}.gatk.vcf.gz
    
    # Create GVCF
    cp ${sample_id}.gatk.vcf.gz ${sample_id}.gatk.g.vcf.gz
    """
}

// ---------------------------------------------------------------------------
// Process: VCF_STATS
// ---------------------------------------------------------------------------
// Generate statistics on called variants

process VCF_STATS {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/bcftools:1.17--h3cc50cf_1'
    
    publishDir "${params.outdir}/variants/stats", mode: 'copy'
    
    input:
    tuple val(sample_id), path(vcf), path(tbi)
    
    output:
    tuple val(sample_id), path("${sample_id}.vcf.stats.txt"), emit: stats
    
    script:
    """
    bcftools stats ${vcf} > ${sample_id}.vcf.stats.txt
    """
}

// ---------------------------------------------------------------------------
// Process: FILTER_VARIANTS
// ---------------------------------------------------------------------------
// Apply quality filters to variants

process FILTER_VARIANTS {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/bcftools:1.17--h3cc50cf_1'
    
    publishDir "${params.outdir}/variants/filtered", mode: 'copy'
    
    input:
    tuple val(sample_id), path(vcf), path(tbi)
    
    output:
    tuple val(sample_id), path("${sample_id}.filtered.vcf.gz"), path("${sample_id}.filtered.vcf.gz.tbi"), emit: vcf
    
    script:
    """
    # Filter for PASS variants with quality >= 30
    bcftools view \\
        -f PASS \\
        -i 'QUAL >= 30' \\
        -O z \\
        -o ${sample_id}.filtered.vcf.gz \\
        ${vcf}
    
    # Index filtered VCF
    bcftools index -t ${sample_id}.filtered.vcf.gz
    """
}

// ---------------------------------------------------------------------------
// Workflow: VARIANT_CALLING
// ---------------------------------------------------------------------------

workflow VARIANT_CALLING {
    take:
    ch_bam        // tuple(sample_id, bam, bai)
    ch_reference  // path to reference FASTA
    
    main:
    // Select variant caller based on parameter
    if (params.use_deepvariant ?: true) {
        DEEPVARIANT_CALL_VARIANTS(ch_bam, ch_reference)
        ch_raw_vcf = DEEPVARIANT_CALL_VARIANTS.out.vcf
        ch_gvcf    = DEEPVARIANT_CALL_VARIANTS.out.gvcf
    } else {
        GATK_HAPLOTYPE_CALLER(ch_bam, ch_reference)
        ch_raw_vcf = GATK_HAPLOTYPE_CALLER.out.vcf
        ch_gvcf    = GATK_HAPLOTYPE_CALLER.out.gvcf
    }
    
    // Generate variant statistics
    VCF_STATS(ch_raw_vcf)
    
    // Filter variants
    FILTER_VARIANTS(ch_raw_vcf)
    
    emit:
    vcf          = ch_raw_vcf
    vcf_filtered = FILTER_VARIANTS.out.vcf
    gvcf         = ch_gvcf
    stats        = VCF_STATS.out.stats
}
