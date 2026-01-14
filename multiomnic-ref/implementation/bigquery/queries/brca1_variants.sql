-- =============================================================================
-- Query: BRCA1 Gene Variants from 1000 Genomes
-- =============================================================================
-- Purpose: Find all variants in the BRCA1 gene from public 1000 Genomes data
-- Data Source: bigquery-public-data.human_genome_variants
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Basic BRCA1 Variant Query
-- -----------------------------------------------------------------------------
-- BRCA1 location (GRCh37): chr17:41,196,312-41,277,500

SELECT
    reference_name,
    start_position,
    end_position,
    reference_bases,
    alternate_bases,
    names AS variant_ids,
    quality,
    filter
FROM
    `bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220`
WHERE
    reference_name = '17'
    AND start_position BETWEEN 41196312 AND 41277500
ORDER BY
    start_position
LIMIT 100;

-- -----------------------------------------------------------------------------
-- BRCA1 Variant Count by Consequence Type
-- -----------------------------------------------------------------------------
-- Note: This query requires annotation data which may not be in the public table

SELECT
    reference_name,
    COUNT(*) AS variant_count,
    COUNT(DISTINCT start_position) AS unique_positions
FROM
    `bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220`
WHERE
    reference_name = '17'
    AND start_position BETWEEN 41196312 AND 41277500
GROUP BY
    reference_name;

-- -----------------------------------------------------------------------------
-- BRCA1 Variants with Allele Frequency Calculation
-- -----------------------------------------------------------------------------

SELECT
    reference_name,
    start_position,
    reference_bases,
    alternate_bases,
    names,
    
    -- Calculate allele frequency from call data
    (
        SELECT 
            SAFE_DIVIDE(
                SUM(CASE WHEN genotype = 1 THEN 1 ELSE 0 END),
                COUNT(*) * 2
            )
        FROM UNNEST(call) AS call_record,
             UNNEST(call_record.genotype) AS genotype
    ) AS calculated_af
    
FROM
    `bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220`
WHERE
    reference_name = '17'
    AND start_position BETWEEN 41196312 AND 41277500
ORDER BY
    start_position
LIMIT 50;

-- -----------------------------------------------------------------------------
-- Population-specific BRCA1 Variant Analysis
-- -----------------------------------------------------------------------------
-- Compare variant frequencies across populations (EUR, AFR, EAS, SAS, AMR)

SELECT
    reference_name,
    start_position,
    reference_bases,
    alternate_bases[OFFSET(0)] AS alt_allele,
    names,
    
    -- Count carriers by population
    (SELECT COUNTIF(call.phaseset IS NOT NULL) 
     FROM UNNEST(call) 
     WHERE EXISTS (SELECT 1 FROM UNNEST(@eur_samples) s WHERE s = call.name)) AS eur_carriers,
    
    (SELECT COUNTIF(call.phaseset IS NOT NULL) 
     FROM UNNEST(call) 
     WHERE EXISTS (SELECT 1 FROM UNNEST(@afr_samples) s WHERE s = call.name)) AS afr_carriers

FROM
    `bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220`
WHERE
    reference_name = '17'
    AND start_position BETWEEN 41196312 AND 41277500
LIMIT 20;

-- -----------------------------------------------------------------------------
-- Clinical BRCA1 Variants from ClinVar (if available)
-- -----------------------------------------------------------------------------
-- Join with ClinVar data to identify pathogenic variants

-- Note: This requires access to ClinVar table which may need separate access
/*
SELECT
    v.reference_name,
    v.start_position,
    v.reference_bases,
    v.alternate_bases,
    c.clinical_significance,
    c.review_status,
    c.phenotypes
FROM
    `bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220` v
JOIN
    `your-project.genomics_warehouse.clinvar` c
ON
    v.reference_name = c.chromosome
    AND v.start_position = c.start
    AND v.reference_bases = c.reference
    AND v.alternate_bases[OFFSET(0)] = c.alternate
WHERE
    v.reference_name = '17'
    AND v.start_position BETWEEN 41196312 AND 41277500
    AND c.clinical_significance LIKE '%Pathogenic%'
ORDER BY
    v.start_position;
*/
