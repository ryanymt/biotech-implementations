#!/usr/bin/env python3
"""
Demo preprocessing task for Cloud Batch.
Simulates genomic data processing while staying within sovereign node.
"""
import os
import time
import random

TASK_INDEX = os.environ.get('BATCH_TASK_INDEX', '0')
PROJECT = os.environ.get('PROJECT_ID', 'unknown')

print(f"=== Task {TASK_INDEX} starting on project {PROJECT} ===")
print(f"Simulating genomic preprocessing (VCF normalization)...")

# Simulate work
for i in range(5):
    time.sleep(1)
    print(f"  Processing chunk {i+1}/5...")

# Simulate output
records = random.randint(100, 500)
print(f"Processed {records} variant records")
print(f"Task {TASK_INDEX} complete - data stays within {PROJECT}")
