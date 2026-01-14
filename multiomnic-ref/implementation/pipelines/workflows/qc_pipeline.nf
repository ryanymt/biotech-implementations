#!/usr/bin/env nextflow

/*
 * =============================================================================
 * Quality Control Pipeline
 * =============================================================================
 * Purpose: Perform QC analysis on BAM files using samtools
 * 
 * Inputs:
 *   - tuple(sample_id, bam, bai)
 * 
 * Outputs:
 *   - report: Text report with QC statistics
 *   - stats: Detailed samtools stats output
 * =============================================================================
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Process: SAMTOOLS_INDEX
// ---------------------------------------------------------------------------
// Create BAM index if not provided

process SAMTOOLS_INDEX {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/samtools:1.17--h00cdaf9_0'
    
    input:
    tuple val(sample_id), path(bam)
    
    output:
    tuple val(sample_id), path(bam), path("${bam}.bai"), emit: indexed_bam
    
    script:
    """
    echo "Indexing BAM file for ${sample_id}..."
    samtools index -@ ${task.cpus} ${bam}
    echo "Index complete for ${sample_id}"
    """
}

// ---------------------------------------------------------------------------
// Process: SAMTOOLS_FLAGSTAT
// ---------------------------------------------------------------------------
// Quick QC check showing read mapping statistics

process SAMTOOLS_FLAGSTAT {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/samtools:1.17--h00cdaf9_0'
    
    publishDir "${params.outdir}/qc/flagstat", mode: 'copy'
    
    input:
    tuple val(sample_id), path(bam)
    
    output:
    tuple val(sample_id), path("${sample_id}.flagstat.txt"), emit: flagstat
    
    script:
    """
    echo "Running samtools flagstat on ${sample_id}..."
    
    samtools flagstat \\
        --threads ${task.cpus} \\
        ${bam} \\
        > ${sample_id}.flagstat.txt
    
    echo "Flagstat complete for ${sample_id}"
    """
}

// ---------------------------------------------------------------------------
// Process: SAMTOOLS_STATS
// ---------------------------------------------------------------------------
// Comprehensive BAM statistics

process SAMTOOLS_STATS {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/samtools:1.17--h00cdaf9_0'
    
    publishDir "${params.outdir}/qc/stats", mode: 'copy'
    
    input:
    tuple val(sample_id), path(bam)
    
    output:
    tuple val(sample_id), path("${sample_id}.stats.txt"), emit: stats
    
    script:
    """
    echo "Running samtools stats on ${sample_id}..."
    
    samtools stats \\
        --threads ${task.cpus} \\
        ${bam} \\
        > ${sample_id}.stats.txt
    
    echo "Stats complete for ${sample_id}"
    """
}

// ---------------------------------------------------------------------------
// Process: SAMTOOLS_IDXSTATS
// ---------------------------------------------------------------------------
// Per-chromosome read counts

process SAMTOOLS_IDXSTATS {
    tag "${sample_id}"
    label 'process_low'
    
    container 'quay.io/biocontainers/samtools:1.17--h00cdaf9_0'
    
    publishDir "${params.outdir}/qc/idxstats", mode: 'copy'
    
    input:
    tuple val(sample_id), path(bam)
    
    output:
    tuple val(sample_id), path("${sample_id}.idxstats.txt"), emit: idxstats
    
    script:
    """
    echo "Running samtools idxstats on ${sample_id}..."
    
    # idxstats requires BAI - generate index first
    echo "Generating BAM index..."
    samtools index -@ ${task.cpus} ${bam}
    
    # Now run idxstats
    samtools idxstats ${bam} > ${sample_id}.idxstats.txt
    
    echo "Idxstats complete for ${sample_id}"
    """
}

// ---------------------------------------------------------------------------
// Process: GENERATE_QC_REPORT
// ---------------------------------------------------------------------------
// Combine all QC metrics into a single report

process GENERATE_QC_REPORT {
    tag "${sample_id}"
    label 'process_low'
    
    publishDir "${params.outdir}/qc/reports", mode: 'copy'
    
    input:
    tuple val(sample_id), path(flagstat), path(stats), path(idxstats)
    
    output:
    tuple val(sample_id), path("${sample_id}.qc_report.txt"), emit: report
    
    script:
    """
    cat << EOF > ${sample_id}.qc_report.txt
================================================================================
                    Quality Control Report: ${sample_id}
================================================================================
Generated: \$(date)

--------------------------------------------------------------------------------
FLAGSTAT SUMMARY
--------------------------------------------------------------------------------
\$(cat ${flagstat})

--------------------------------------------------------------------------------
CHROMOSOME COVERAGE (Top 10)
--------------------------------------------------------------------------------
\$(head -10 ${idxstats})

--------------------------------------------------------------------------------
DETAILED STATISTICS
--------------------------------------------------------------------------------
\$(grep -E "^SN" ${stats} | head -20)

================================================================================
                              End of Report
================================================================================
EOF
    """
}

// ---------------------------------------------------------------------------
// Workflow: QC_PIPELINE
// ---------------------------------------------------------------------------

workflow QC_PIPELINE {
    take:
    ch_bam_input  // tuple(sample_id, bam)
    
    main:
    // Run all QC tools in parallel (each handles BAM-only input)
    SAMTOOLS_FLAGSTAT(ch_bam_input)
    SAMTOOLS_STATS(ch_bam_input)
    SAMTOOLS_IDXSTATS(ch_bam_input)  // generates index internally
    
    // Combine outputs for report generation
    ch_qc_inputs = SAMTOOLS_FLAGSTAT.out.flagstat
        .join(SAMTOOLS_STATS.out.stats)
        .join(SAMTOOLS_IDXSTATS.out.idxstats)
    
    // Generate combined report
    GENERATE_QC_REPORT(ch_qc_inputs)
    
    emit:
    flagstat = SAMTOOLS_FLAGSTAT.out.flagstat
    stats    = SAMTOOLS_STATS.out.stats
    idxstats = SAMTOOLS_IDXSTATS.out.idxstats
    report   = GENERATE_QC_REPORT.out.report
}
