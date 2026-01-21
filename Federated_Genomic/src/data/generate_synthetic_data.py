#!/usr/bin/env python3
"""Synthetic Patient Genomic Data Generator"""

import numpy as np
import pandas as pd
import sys

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
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
    generate_patient_data(n, "US").to_csv("data_us.csv", index=False)
    generate_patient_data(n, "EU", seed=123).to_csv("data_eu.csv", index=False)
    print(f"Generated {n} records each for US and EU")
