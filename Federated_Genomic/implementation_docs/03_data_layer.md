# Phase 3: Data Layer

## Objective

Set up sovereign data stores in each node with BigQuery datasets encrypted using CMEK, and populate with synthetic patient genomic data.

## Deliverables

- [x] BigQuery datasets in US and EU nodes
- [x] CMEK encryption configured
- [x] Synthetic data generation script
- [x] 1,000 patient records per node

---

## 3.1 Data Schema

```
Table: patient_genomic_data
├── patient_id (STRING)      # UUID e.g., "US-0001"
├── age (INTEGER)            # 25-80
├── variant_brca1 (INTEGER)  # 0, 1, or 2 (allele count)
├── variant_tp53 (INTEGER)   # 0, 1, or 2
├── variant_apoe4 (INTEGER)  # 0, 1, or 2
├── bmi (FLOAT)              # 18.5-40.0
└── diagnosis_cancer (INTEGER) # 0 or 1 (TARGET)
```

## 3.2 Create BigQuery Datasets

### US Node

```bash
bq mk \
  --project_id=fed-node-us \
  --dataset \
  --location=us-central1 \
  --default_kms_key=projects/fed-node-us/locations/us-central1/keyRings/genomics-keyring/cryptoKeys/patient-data-key \
  hospital_data
```

### EU Node

```bash
# First create KMS key in EU region
gcloud kms keyrings create genomics-keyring \
  --project=fed-node-eu \
  --location=europe-west2

gcloud kms keys create patient-data-key \
  --project=fed-node-eu \
  --location=europe-west2 \
  --keyring=genomics-keyring \
  --purpose=encryption

# Create dataset
bq mk \
  --project_id=fed-node-eu \
  --dataset \
  --location=europe-west2 \
  --default_kms_key=projects/fed-node-eu/locations/europe-west2/keyRings/genomics-keyring/cryptoKeys/patient-data-key \
  hospital_data
```

## 3.3 Synthetic Data Generator

Create `src/data/generate_synthetic_data.py`:

```python
#!/usr/bin/env python3
"""Synthetic Patient Genomic Data Generator"""

import numpy as np
import pandas as pd

def generate_patient_data(n_patients: int, region: str, seed: int = 42):
    np.random.seed(seed)
    
    if region == "US":
        prefix, age_mean, bmi_mean = "US", 52, 28.5
        brca1_prob = [0.85, 0.12, 0.03]
    else:
        prefix, age_mean, bmi_mean = "EU", 48, 25.0
        brca1_prob = [0.92, 0.06, 0.02]
    
    patient_ids = [f"{prefix}-{str(i).zfill(4)}" for i in range(1, n_patients + 1)]
    ages = np.clip(np.random.normal(age_mean, 12, n_patients).astype(int), 25, 80)
    bmis = np.clip(np.random.normal(bmi_mean, 4, n_patients), 18.5, 45.0)
    variant_brca1 = np.random.choice([0, 1, 2], n_patients, p=brca1_prob)
    variant_tp53 = np.random.choice([0, 1, 2], n_patients, p=[0.90, 0.08, 0.02])
    variant_apoe4 = np.random.choice([0, 1, 2], n_patients, p=[0.80, 0.15, 0.05])
    
    logits = -3.0 + 0.03*(ages-50) + 0.8*variant_brca1 + 0.5*variant_tp53
    probs = 1 / (1 + np.exp(-logits))
    diagnosis_cancer = (np.random.random(n_patients) < probs).astype(int)
    
    return pd.DataFrame({
        'patient_id': patient_ids, 'age': ages, 'variant_brca1': variant_brca1,
        'variant_tp53': variant_tp53, 'variant_apoe4': variant_apoe4,
        'bmi': np.round(bmis, 1), 'diagnosis_cancer': diagnosis_cancer
    })

if __name__ == "__main__":
    generate_patient_data(1000, "US").to_csv("data_us.csv", index=False)
    generate_patient_data(1000, "EU", seed=123).to_csv("data_eu.csv", index=False)
```

## 3.4 Load Data to BigQuery

```bash
# Upload to US node
bq load --source_format=CSV --skip_leading_rows=1 \
  fed-node-us:hospital_data.patient_genomic_data ./data_us.csv

# Upload to EU node
bq load --source_format=CSV --skip_leading_rows=1 \
  fed-node-eu:hospital_data.patient_genomic_data ./data_eu.csv
```

## 3.5 Verification

```sql
SELECT 'US' as region, COUNT(*) as n, AVG(diagnosis_cancer) as cancer_rate
FROM `fed-node-us.hospital_data.patient_genomic_data`
UNION ALL
SELECT 'EU', COUNT(*), AVG(diagnosis_cancer)
FROM `fed-node-eu.hospital_data.patient_genomic_data`;
```

| Region | N | Cancer Rate |
|--------|---|-------------|
| US | 1000 | ~15% |
| EU | 1000 | ~10% |

---

→ Proceed to [04_federation_engine.md](./04_federation_engine.md)
