# Phase 8: Looker Studio Dashboards

## Objective

Create interactive dashboards for genomic analytics and compliance reporting, enabling researchers to visualize variant data without direct data access.

> **Note**: All dashboards connect to BigQuery within the VPC-SC perimeter—only aggregated statistics are displayed, never raw patient data.

---

## 8.1 Dashboard Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SOVEREIGN NODE DATA GOVERNANCE                            │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  BigQuery (CMEK Encrypted, VPC-SC Protected)                         │    │
│  │  └── genomics_warehouse.variants                                    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              │                                              │
│                              │ Aggregated queries only                      │
│                              ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Looker Studio Dashboard                                             │    │
│  │  • Variant QC metrics (no PII)                                      │    │
│  │  • Population statistics (aggregates)                                │    │
│  │  • Compliance summaries                                              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 8.2 Connect Looker Studio to BigQuery

1. Go to **[Looker Studio](https://lookerstudio.google.com)**
2. Click **Create** → **Report**
3. Click **Add data** → **BigQuery**
4. Navigate: **fedgen-node-us** → **genomics_warehouse** → **variants**
5. Click **Add**

## 8.3 Recommended Dashboard Components

### Scorecards
| Metric | Description |
|--------|-------------|
| Total Variants | Overall variant count |
| PASS Rate | Percentage passing QC filters |
| Avg Quality | Mean Phred-scaled quality |

### Charts
| Chart | Dimension | Metric |
|-------|-----------|--------|
| Bar: Variants by Chromosome | `reference_name` | Record Count |
| Pie: Filter Distribution | `filter` | Record Count |
| Histogram: Quality Distribution | `quality` (binned) | Record Count |

### Sample Layout
```
┌─────────────────────────────────────────────────────────────┐
│  Variant Analysis Dashboard - Sovereign Node US             │
├─────────────┬─────────────┬─────────────────────────────────┤
│  TOTAL      │  PASS RATE  │  [Chromosome Filter Dropdown]   │
│  3,492,497  │  91.7%      │                                 │
├─────────────────────────────────────────────────────────────┤
│  [Variants by Chromosome]     [PASS vs RefCall Pie Chart]   │
├─────────────────────────────────────────────────────────────┤
│  [Quality Distribution]       [Top Variant Types Table]     │
└─────────────────────────────────────────────────────────────┘
```

## 8.4 Useful Queries

### Variants per Chromosome
```sql
SELECT reference_name, COUNT(*) as count
FROM `fedgen-node-us.genomics_warehouse.variants`
GROUP BY reference_name
ORDER BY count DESC
```

### Quality Distribution
```sql
SELECT 
  FLOOR(quality / 10) * 10 as quality_bin,
  COUNT(*) as count
FROM `fedgen-node-us.genomics_warehouse.variants`
WHERE 'PASS' IN UNNEST(filter)
GROUP BY quality_bin
ORDER BY quality_bin
```

### Transition vs Transversion
```sql
SELECT
  CASE 
    WHEN (reference_bases = 'A' AND alternate_bases[OFFSET(0)] = 'G') 
      OR (reference_bases = 'G' AND alternate_bases[OFFSET(0)] = 'A')
      OR (reference_bases = 'C' AND alternate_bases[OFFSET(0)] = 'T')
      OR (reference_bases = 'T' AND alternate_bases[OFFSET(0)] = 'C')
    THEN 'Transition'
    ELSE 'Transversion'
  END as variant_type,
  COUNT(*) as count
FROM `fedgen-node-us.genomics_warehouse.variants`
WHERE 'PASS' IN UNNEST(filter)
GROUP BY variant_type
```

## 8.5 Compliance Considerations

| Requirement | Implementation |
|-------------|----------------|
| **No PII exposed** | Dashboard shows aggregates only, not sample-level data |
| **Audit logging** | All BigQuery queries logged for compliance |
| **Access control** | Looker Studio respects BigQuery IAM bindings |
| **Data stays local** | VPC-SC ensures data doesn't leave sovereign perimeter |

---

→ Return to [00_overview.md](./00_overview.md) for the complete implementation index
