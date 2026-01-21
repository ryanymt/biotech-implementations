#!/usr/bin/env python3
"""Synthetic Patient Genomic Data Generator - stdlib only"""
import random
import csv
import math

def normal(mu, sigma):
    """Box-Muller transform for normal distribution"""
    u1, u2 = random.random(), random.random()
    return mu + sigma * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)

def choice(options, probs):
    r = random.random()
    cumsum = 0
    for opt, p in zip(options, probs):
        cumsum += p
        if r <= cumsum:
            return opt
    return options[-1]

def generate_data(n, region, seed):
    random.seed(seed)
    if region == "US":
        prefix, age_mean, bmi_mean = "US", 52, 28.5
        brca1_prob = [0.85, 0.12, 0.03]
    else:
        prefix, age_mean, bmi_mean = "EU", 48, 25.0
        brca1_prob = [0.92, 0.06, 0.02]
    
    rows = []
    for i in range(1, n+1):
        age = max(25, min(80, int(normal(age_mean, 12))))
        bmi = round(max(18.5, min(45.0, normal(bmi_mean, 4))), 1)
        brca1 = choice([0, 1, 2], brca1_prob)
        tp53 = choice([0, 1, 2], [0.90, 0.08, 0.02])
        apoe4 = choice([0, 1, 2], [0.80, 0.15, 0.05])
        logit = -3.0 + 0.03*(age-50) + 0.8*brca1 + 0.5*tp53
        prob = 1 / (1 + math.exp(-logit))
        cancer = 1 if random.random() < prob else 0
        rows.append([f"{prefix}-{i:04d}", age, brca1, tp53, apoe4, bmi, cancer])
    return rows

with open("data_us.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["patient_id","age","variant_brca1","variant_tp53","variant_apoe4","bmi","diagnosis_cancer"])
    w.writerows(generate_data(1000, "US", 42))
with open("data_eu.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["patient_id","age","variant_brca1","variant_tp53","variant_apoe4","bmi","diagnosis_cancer"])
    w.writerows(generate_data(1000, "EU", 123))
print("Generated data_us.csv and data_eu.csv (1000 records each)")
