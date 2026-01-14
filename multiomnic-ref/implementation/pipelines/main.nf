#!/usr/bin/env nextflow

/*
 * =============================================================================
 * Cloud-Native Multiomics Platform - Main Pipeline
 * =============================================================================
 * Purpose: Orchestrate genomic analysis workflows from raw data to insights
 * 
 * Usage:
 *   nextflow run main.nf -profile gcp --sample_id HG00119
 *   nextflow run main.nf -profile test  # Quick test with public data
 * =============================================================================
 */

nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Imports
// ---------------------------------------------------------------------------
include { QC_PIPELINE } from './workflows/qc_pipeline'
include { VARIANT_CALLING } from './workflows/variant_calling'
include { VCF_TO_BIGQUERY } from './workflows/vcf_to_bigquery'


// ---------------------------------------------------------------------------
// Help Message
// ---------------------------------------------------------------------------
def helpMessage() {
    log.info """
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║           Cloud-Native Multiomics Platform - Genomics Pipeline            ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
    
    Usage:
      nextflow run main.nf -profile <profile> [options]
    
    Profiles:
      local     Run locally with Docker
      gcp       Run on Google Cloud Batch (production)
      test      Quick test with 1000 Genomes sample
    
    Required:
      --sample_id     Sample identifier (e.g., HG00119)
      --input_bam     Path to input BAM file (gs:// or local)
    
    Optional:
      --outdir        Output directory [default: ${params.outdir}]
      --reference     Reference genome FASTA [default: hg38]
      --skip_qc       Skip QC steps [default: false]
    
    Examples:
      # Run QC on public 1000 Genomes sample
      nextflow run main.nf -profile gcp --sample_id HG00119
      
      # Run full pipeline on custom BAM
      nextflow run main.nf -profile gcp \\
        --sample_id MY_SAMPLE \\
        --input_bam gs://my-bucket/data/sample.bam
    """.stripIndent()
}

// ---------------------------------------------------------------------------
// Parameter Validation
// ---------------------------------------------------------------------------
def validateParams() {
    // Check required parameters
    if (!params.sample_id) {
        error "ERROR: --sample_id is required. Use --help for usage information."
    }
    
    // Log configuration
    log.info """
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                         Pipeline Configuration                            ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
    
    Sample ID   : ${params.sample_id}
    Input BAM   : ${params.input_bam ?: 'Auto-detect from 1000 Genomes'}
    Output Dir  : ${params.outdir}
    Reference   : ${params.reference}
    Skip QC     : ${params.skip_qc}
    
    ═══════════════════════════════════════════════════════════════════════════
    """.stripIndent()
}

// ---------------------------------------------------------------------------
// Input Channels
// ---------------------------------------------------------------------------

// Resolve BAM file from sample ID if not provided
def getInputBam() {
    if (params.input_bam) {
        return params.input_bam
    }
    // Auto-detect from 1000 Genomes public data
    return "${params.public_1000g}bam/${params.sample_id}.mapped.ILLUMINA.bwa.GBR.low_coverage.20120522.bam"
}

// ---------------------------------------------------------------------------
// Main Workflow
// ---------------------------------------------------------------------------
workflow {
    // Show help and exit
    if (params.help) {
        helpMessage()
        exit 0
    }
    
    // Validate parameters
    validateParams()
    
    // Create input channel
    ch_bam = Channel.fromPath(getInputBam(), checkIfExists: false)
        .map { bam -> 
            return tuple(params.sample_id, bam)
        }
    
    // Run QC Pipeline
    if (!params.skip_qc) {
        QC_PIPELINE(ch_bam)
        ch_qc_report = QC_PIPELINE.out.report
    }
    
    // Run Variant Calling (requires GPU for DeepVariant)
    if (params.run_variant_calling) {
        ch_reference = Channel.fromPath(params.reference, checkIfExists: false)
        
        // Add BAM index channel (assumes .bai exists alongside .bam)
        ch_bam_indexed = ch_bam.map { sample_id, bam ->
            def bai = file("${bam}.bai")
            return tuple(sample_id, bam, bai)
        }
        
        VARIANT_CALLING(ch_bam_indexed, ch_reference)
        ch_vcf = VARIANT_CALLING.out.vcf_filtered
        
        // Load variants to BigQuery (if enabled)
        if (params.load_to_bigquery) {
            // Extract just sample_id and vcf path (drop index)
            ch_vcf_for_bq = ch_vcf.map { sample_id, vcf, tbi -> 
                return tuple(sample_id, vcf)
            }
            VCF_TO_BIGQUERY(ch_vcf_for_bq)
        }
    }
}


// ---------------------------------------------------------------------------
// Workflow Events
// ---------------------------------------------------------------------------
workflow.onComplete {
    def status = workflow.success ? 'SUCCESS' : 'FAILED'
    def color = workflow.success ? '\033[0;32m' : '\033[0;31m'
    
    log.info """
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                         Pipeline Complete: ${status}                         ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
    
    ${color}Status    : ${status}\033[0m
    Duration  : ${workflow.duration}
    Output    : ${params.outdir}
    
    Reports:
      - Report   : ${params.outdir}/pipeline_report.html
      - Timeline : ${params.outdir}/timeline.html
      - Trace    : ${params.outdir}/trace.txt
    
    ═══════════════════════════════════════════════════════════════════════════
    """.stripIndent()
}

workflow.onError {
    log.error """
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                           Pipeline Error                                  ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
    
    Error Message: ${workflow.errorMessage}
    
    Please check the error logs and retry with --resume
    
    ═══════════════════════════════════════════════════════════════════════════
    """.stripIndent()
}
