-- =============================================================================
-- Query: Population Cohort Analysis
-- =============================================================================
-- Purpose: Demonstrate cohort building and population-scale statistics
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Cohort Size by Population
-- -----------------------------------------------------------------------------

SELECT
    p.super_population,
    p.population,
    COUNT(DISTINCT s.sample_id) AS sample_count
FROM
    `genomics_warehouse.samples` s
JOIN
    `bigquery-public-data.human_genome_variants.1000_genomes_populations` p
ON
    s.sample_id = p.sample_id
GROUP BY
    p.super_population, p.population
ORDER BY
    p.super_population, sample_count DESC;

-- -----------------------------------------------------------------------------
-- 2. Variant Allele Frequency Distribution
-- -----------------------------------------------------------------------------
-- Bin variants by allele frequency to understand the frequency spectrum

SELECT
    CASE
        WHEN gnomad_af IS NULL THEN 'Novel (Not in gnomAD)'
        WHEN gnomad_af < 0.0001 THEN 'Ultra-rare (<0.01%)'
        WHEN gnomad_af < 0.001 THEN 'Very rare (0.01-0.1%)'
        WHEN gnomad_af < 0.01 THEN 'Rare (0.1-1%)'
        WHEN gnomad_af < 0.05 THEN 'Low frequency (1-5%)'
        ELSE 'Common (>5%)'
    END AS frequency_bin,
    COUNT(*) AS variant_count
FROM
    `genomics_warehouse.variant_summary`
GROUP BY
    frequency_bin
ORDER BY
    variant_count DESC;

-- -----------------------------------------------------------------------------
-- 3. Genes with Most High-Impact Variants
-- -----------------------------------------------------------------------------

SELECT
    gene_symbol,
    COUNT(*) AS total_variants,
    COUNTIF(impact = 'HIGH') AS high_impact,
    COUNTIF(impact = 'MODERATE') AS moderate_impact,
    COUNTIF(impact = 'LOW') AS low_impact,
    ROUND(SAFE_DIVIDE(COUNTIF(impact = 'HIGH'), COUNT(*)) * 100, 2) AS pct_high_impact
FROM
    `genomics_warehouse.variant_summary`
WHERE
    gene_symbol IS NOT NULL
GROUP BY
    gene_symbol
HAVING
    total_variants >= 10
ORDER BY
    high_impact DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- 4. Case-Control Variant Burden Test
-- -----------------------------------------------------------------------------
-- Compare variant counts between cases and controls for a specific gene

WITH variant_counts AS (
    SELECT
        s.sample_id,
        s.disease_status,
        COUNT(DISTINCT CONCAT(v.reference_name, ':', CAST(v.start_position AS STRING))) AS variant_count
    FROM
        `genomics_warehouse.samples` s
    JOIN
        `genomics_warehouse.variants` v
    ON
        s.sample_id IN (SELECT c.sample_id FROM UNNEST(v.calls) c)
    JOIN
        UNNEST(v.annotations) a
    WHERE
        a.gene_symbol = 'BRCA1'  -- Replace with gene of interest
        AND a.impact IN ('HIGH', 'MODERATE')
    GROUP BY
        s.sample_id, s.disease_status
)
SELECT
    disease_status,
    COUNT(*) AS sample_count,
    AVG(variant_count) AS avg_variants,
    STDDEV(variant_count) AS std_variants,
    MIN(variant_count) AS min_variants,
    MAX(variant_count) AS max_variants
FROM
    variant_counts
GROUP BY
    disease_status;

-- -----------------------------------------------------------------------------
-- 5. Crossover Query: Your Sample vs 1000 Genomes
-- -----------------------------------------------------------------------------
-- Compare mutation rate of your sample against global population

WITH your_sample_stats AS (
    SELECT
        COUNT(*) AS your_variant_count,
        COUNTIF(gnomad_af < 0.01) AS your_rare_count
    FROM
        `genomics_warehouse.variant_summary`
    WHERE
        EXISTS (
            SELECT 1 FROM `genomics_warehouse.samples` s 
            WHERE s.sample_id = 'YOUR_SAMPLE_ID'  -- Replace with your sample
        )
),
population_stats AS (
    SELECT
        COUNT(*) / 2504 AS avg_variant_count,  -- 2504 samples in 1000G Phase 3
        AVG(quality) AS avg_quality
    FROM
        `bigquery-public-data.human_genome_variants.1000_genomes_phase_3_variants_20150220`
    WHERE
        reference_name = '17'  -- Example: chromosome 17
)
SELECT
    y.your_variant_count,
    y.your_rare_count,
    p.avg_variant_count AS population_avg,
    ROUND(SAFE_DIVIDE(y.your_variant_count, p.avg_variant_count) * 100 - 100, 2) AS pct_diff_from_avg
FROM
    your_sample_stats y,
    population_stats p;

-- -----------------------------------------------------------------------------
-- 6. Variant Transition/Transversion Ratio (Ti/Tv)
-- -----------------------------------------------------------------------------
-- Quality metric: expected Ti/Tv ~2.0 for WGS, ~2.5 for WES

SELECT
    CASE
        WHEN (reference_bases = 'A' AND alternate_base = 'G') OR
             (reference_bases = 'G' AND alternate_base = 'A') OR
             (reference_bases = 'C' AND alternate_base = 'T') OR
             (reference_bases = 'T' AND alternate_base = 'C')
        THEN 'Transition'
        ELSE 'Transversion'
    END AS mutation_type,
    COUNT(*) AS count
FROM
    `genomics_warehouse.variant_summary`
WHERE
    LENGTH(reference_bases) = 1
    AND LENGTH(alternate_base) = 1
GROUP BY
    mutation_type;
