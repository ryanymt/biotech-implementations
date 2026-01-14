-- =============================================================================
-- Cloud-Native Multiomics Platform - BigQuery Schemas
-- =============================================================================
-- Purpose: Define table schemas for genomic variants, annotations, and phenotypes
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Dataset: genomics_warehouse
-- -----------------------------------------------------------------------------
-- Note: Dataset is created via Terraform (apis.tf)
-- These are the table schemas within the dataset

-- -----------------------------------------------------------------------------
-- Table: variants
-- -----------------------------------------------------------------------------
-- Stores genomic variants from VCF files (via Variant Transforms)

CREATE TABLE IF NOT EXISTS `genomics_warehouse.variants`
(
    -- Variant identification
    reference_name      STRING NOT NULL,           -- Chromosome (chr1, chr2, ..., chrX, chrY, chrM)
    start_position      INT64 NOT NULL,            -- 0-based start position
    end_position        INT64 NOT NULL,            -- 0-based end position
    reference_bases     STRING NOT NULL,           -- Reference allele
    alternate_bases     ARRAY<STRING> NOT NULL,    -- Alternate allele(s)
    
    -- Variant metadata
    variant_id          STRING,                    -- dbSNP ID (rs number)
    quality             FLOAT64,                   -- QUAL score from VCF
    filter              ARRAY<STRING>,             -- FILTER status (PASS, etc.)
    
    -- Sample-level data
    calls               ARRAY<STRUCT<
        sample_id       STRING,
        genotype        ARRAY<INT64>,             -- 0=ref, 1=alt1, 2=alt2, etc.
        genotype_quality INT64,
        read_depth      INT64,
        allele_depths   ARRAY<INT64>
    >>,
    
    -- Annotations (from VEP/Ensembl)
    annotations         ARRAY<STRUCT<
        gene_symbol     STRING,
        gene_id         STRING,
        transcript_id   STRING,
        consequence     STRING,                    -- missense_variant, synonymous, etc.
        impact          STRING,                    -- HIGH, MODERATE, LOW, MODIFIER
        amino_acid_change STRING,
        codon_change    STRING
    >>,
    
    -- Population frequencies
    population_frequencies STRUCT<
        gnomad_af       FLOAT64,                   -- gnomAD allele frequency
        gnomad_af_nfe   FLOAT64,                   -- Non-Finnish European
        gnomad_af_afr   FLOAT64,                   -- African
        gnomad_af_eas   FLOAT64                    -- East Asian
    >,
    
    -- Clinical significance
    clinical_significance STRING,                  -- From ClinVar
    
    -- Metadata
    source_file         STRING,                    -- Original VCF file path
    ingestion_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(ingestion_timestamp)
CLUSTER BY reference_name, start_position;

-- -----------------------------------------------------------------------------
-- Table: samples
-- -----------------------------------------------------------------------------
-- Sample metadata and phenotype information

CREATE TABLE IF NOT EXISTS `genomics_warehouse.samples`
(
    sample_id           STRING NOT NULL,
    
    -- Demographics
    study_id            STRING,
    population          STRING,                    -- EUR, AFR, EAS, SAS, AMR
    super_population    STRING,
    sex                 STRING,                    -- male, female, unknown
    
    -- Sequencing metadata
    sequencing_center   STRING,
    sequencing_platform STRING,
    coverage            FLOAT64,
    capture_kit         STRING,
    
    -- Phenotype data
    phenotypes          ARRAY<STRUCT<
        phenotype_id    STRING,                    -- HPO term or ICD code
        phenotype_name  STRING,
        present         BOOL
    >>,
    
    -- Disease associations
    disease_status      STRING,                    -- case, control, unknown
    disease_name        STRING,
    
    -- Timestamps
    collection_date     DATE,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- Table: genes
-- -----------------------------------------------------------------------------
-- Gene annotations and metadata

CREATE TABLE IF NOT EXISTS `genomics_warehouse.genes`
(
    gene_id             STRING NOT NULL,           -- Ensembl gene ID (ENSG...)
    gene_symbol         STRING NOT NULL,           -- HGNC symbol (BRCA1, TP53, etc.)
    gene_name           STRING,                    -- Full gene name
    
    -- Location
    chromosome          STRING,
    start_position      INT64,
    end_position        INT64,
    strand              STRING,                    -- + or -
    
    -- Gene type
    gene_type           STRING,                    -- protein_coding, lncRNA, etc.
    
    -- Annotations
    description         STRING,
    omim_id             STRING,
    hgnc_id             STRING,
    
    -- Constraint scores (from gnomAD)
    pli_score           FLOAT64,                   -- Probability of LoF intolerance
    loeuf_score         FLOAT64,                   -- LoF observed/expected upper bound
    mis_z_score         FLOAT64,                   -- Missense Z-score
    
    -- Pathway associations
    go_terms            ARRAY<STRING>,
    kegg_pathways       ARRAY<STRING>
);

-- -----------------------------------------------------------------------------
-- View: variant_summary
-- -----------------------------------------------------------------------------
-- Aggregated view for common queries

CREATE OR REPLACE VIEW `genomics_warehouse.variant_summary` AS
SELECT
    v.reference_name,
    v.start_position,
    v.reference_bases,
    v.alternate_bases[OFFSET(0)] AS alternate_base,
    v.variant_id,
    v.quality,
    
    -- Annotation summary
    (SELECT a.gene_symbol FROM UNNEST(v.annotations) a LIMIT 1) AS gene_symbol,
    (SELECT a.consequence FROM UNNEST(v.annotations) a LIMIT 1) AS consequence,
    (SELECT a.impact FROM UNNEST(v.annotations) a LIMIT 1) AS impact,
    
    -- Population frequency
    v.population_frequencies.gnomad_af AS gnomad_af,
    
    -- Sample counts
    ARRAY_LENGTH(v.calls) AS sample_count,
    
    -- Allele counts
    (SELECT COUNTIF(1 IN UNNEST(c.genotype)) FROM UNNEST(v.calls) c) AS alt_allele_count
    
FROM `genomics_warehouse.variants` v;
