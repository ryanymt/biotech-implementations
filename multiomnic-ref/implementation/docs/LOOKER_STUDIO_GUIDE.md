# Looker Studio Dashboard Guide

> **For:** DeepVariant Variants from `multiomnic-ref.genomics_warehouse.deepvariant_variants`

---

## Data Overview

| Metric | Value |
|--------|-------|
| **Total Variants** | 3,492,497 |
| **Chromosomes** | 24 |
| **PASS Rate** | 91.7% (3,201,590) |
| **RefCall Rate** | 8.3% (290,907) |
| **Quality Range** | 0.0 - 59.1 |
| **Avg Quality** | 26.57 |

### Table Schema

| Field | Type | Description |
|-------|------|-------------|
| `chromosome` | STRING | Chromosome (1-22, X, Y) |
| `position` | INTEGER | Genomic position |
| `id` | STRING | Variant ID (usually ".") |
| `ref` | STRING | Reference allele |
| `alt` | STRING | Alternate allele(s) |
| `quality` | FLOAT | Phred-scaled quality score |
| `filter` | STRING | PASS or RefCall |

---

## Step 1: Connect to BigQuery

1. Go to **[Looker Studio](https://lookerstudio.google.com)**
2. Click **Create** → **Report**
3. Click **Add data** → **BigQuery**
4. Navigate: **multiomnic-ref** → **genomics_warehouse** → **deepvariant_variants**
5. Click **Add**

---

## Step 2: Create Dashboard Components

### 2.1 Scorecard: Total Variants

1. Click **Add a chart** → **Scorecard**
2. Set:
   - **Metric:** `Record Count`
   - **Name:** "Total Variants"
3. Style: Large font, blue color

### 2.2 Bar Chart: Variants per Chromosome

1. Click **Add a chart** → **Bar chart**
2. Set:
   - **Dimension:** `chromosome`
   - **Metric:** `Record Count`
   - **Sort:** `Record Count` (Descending)
3. Title: "Variants by Chromosome"

### 2.3 Pie Chart: Filter Distribution

1. Click **Add a chart** → **Pie chart**
2. Set:
   - **Dimension:** `filter`
   - **Metric:** `Record Count`
3. Title: "PASS vs RefCall"
4. Expected: ~92% PASS, ~8% RefCall

### 2.4 Histogram: Quality Score Distribution

1. Click **Add a chart** → **Bar chart**
2. Set:
   - **Dimension:** `quality` (or create a calculated field for bins)
   - **Metric:** `Record Count`
3. Title: "Quality Score Distribution"

### 2.5 Table: Top Variant Types

1. Click **Add a chart** → **Table**
2. Set:
   - **Dimensions:** `ref`, `alt`
   - **Metric:** `Record Count`
   - **Sort:** `Record Count` (Descending)
   - **Rows:** 10
3. Title: "Most Common Variant Types"

Expected top results:
| ref | alt | count |
|-----|-----|-------|
| C | T | 515,326 |
| G | A | 514,617 |
| T | C | 489,515 |
| A | G | 489,175 |

### 2.6 Filter Controls (Optional)

1. Click **Add a control** → **Drop-down list**
2. Set:
   - **Dimension:** `chromosome`
3. This allows users to filter the entire dashboard by chromosome

---

## Step 3: Add Title and Styling

1. **Title:** "DeepVariant Analysis Dashboard - HG00119"
2. **Subtitle:** "3.49M variants from whole genome sequencing"
3. **Color scheme:** Professional blues/greens
4. **Logo:** Add Google Cloud logo if desired

---

## Sample Layout

```
┌─────────────────────────────────────────────────────────────┐
│  DeepVariant Analysis Dashboard - HG00119                   │
├─────────────┬─────────────┬─────────────────────────────────┤
│  TOTAL      │  PASS RATE  │  [Chromosome Filter Dropdown]   │
│  3,492,497  │  91.7%      │                                 │
├─────────────┴─────────────┴─────────────────────────────────┤
│  ┌────────────────────────┐ ┌────────────────────────────┐  │
│  │ Variants by Chromosome │ │ PASS vs RefCall Pie Chart  │  │
│  │ [Bar Chart]           │ │ [Pie Chart]                │  │
│  └────────────────────────┘ └────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌────────────────────────┐ ┌────────────────────────────┐  │
│  │ Quality Distribution   │ │ Top Variant Types         │  │
│  │ [Histogram]           │ │ [Table]                   │  │
│  └────────────────────────┘ └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Direct Link

After creating, share the dashboard:
1. Click **Share** → **Get report link**
2. Set **Link settings** → "Anyone with the link can view"

---

## BigQuery Console

Query the data directly:
```
https://console.cloud.google.com/bigquery?project=multiomnic-ref&ws=!1m5!1m4!4m3!1smultiomnic-ref!2sgenomics_warehouse!3sdeepvariant_variants
```

---

## Useful Queries for Custom Charts

### Variants per Chromosome
```sql
SELECT chromosome, COUNT(*) as count
FROM `multiomnic-ref.genomics_warehouse.deepvariant_variants`
GROUP BY chromosome
ORDER BY count DESC
```

### Quality Distribution Bins
```sql
SELECT 
  FLOOR(quality / 10) * 10 as quality_bin,
  COUNT(*) as count
FROM `multiomnic-ref.genomics_warehouse.deepvariant_variants`
WHERE filter = 'PASS'
GROUP BY quality_bin
ORDER BY quality_bin
```

### Transition vs Transversion
```sql
SELECT
  CASE 
    WHEN (ref = 'A' AND alt = 'G') OR (ref = 'G' AND alt = 'A') 
      OR (ref = 'C' AND alt = 'T') OR (ref = 'T' AND alt = 'C')
    THEN 'Transition'
    ELSE 'Transversion'
  END as variant_type,
  COUNT(*) as count
FROM `multiomnic-ref.genomics_warehouse.deepvariant_variants`
WHERE filter = 'PASS' AND LENGTH(ref) = 1 AND LENGTH(alt) = 1
GROUP BY variant_type
```
