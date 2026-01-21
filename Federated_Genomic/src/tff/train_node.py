#!/usr/bin/env python3
"""
Federated Training Node - Simulates local model training on sovereign data.

This script:
1. Loads patient data from the node's local BigQuery dataset
2. Trains a simple logistic regression model
3. Outputs model weights (what would be sent to the hub)
4. Logs progress clearly for demo purposes

Environment variables:
- PROJECT_ID: The GCP project for this node
- NODE_ID: Identifier for this node (US, EU, SG)
- DATASET: BigQuery dataset name (default: hospital_data)
- TABLE: BigQuery table name (default: patient_genomic_data)
"""

import os
import sys
import time
import json
import numpy as np

# Simulated training parameters
EPOCHS = 5
BATCH_SIZE = 32

def log(message):
    """Print with timestamp for demo visibility."""
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{timestamp}] {message}", flush=True)

def load_data_from_bigquery(project_id, dataset, table):
    """Load training data from BigQuery."""
    log(f"📊 Connecting to BigQuery: {project_id}.{dataset}.{table}")
    
    try:
        from google.cloud import bigquery
        client = bigquery.Client(project=project_id)
        
        query = f"""
        SELECT 
            age,
            variant_brca1,
            variant_tp53,
            variant_apoe4,
            bmi,
            diagnosis_cancer
        FROM `{project_id}.{dataset}.{table}`
        """
        
        log("📥 Loading patient data (data stays in this region)...")
        df = client.query(query).to_dataframe()
        
        log(f"✓ Loaded {len(df)} patient records")
        return df
        
    except Exception as e:
        log(f"⚠️  BigQuery not available, using simulated data: {e}")
        # Simulate data for testing
        np.random.seed(42)
        n_samples = 1000
        return {
            'age': np.random.randint(30, 80, n_samples),
            'variant_brca1': np.random.randint(0, 2, n_samples),
            'variant_tp53': np.random.randint(0, 2, n_samples),
            'variant_apoe4': np.random.randint(0, 2, n_samples),
            'bmi': np.random.uniform(20, 35, n_samples),
            'diagnosis_cancer': np.random.randint(0, 2, n_samples)
        }

def train_model(data, node_id):
    """Train a simple model locally and return weights."""
    log(f"🧠 Starting local training on {node_id} node...")
    log(f"   (Data NEVER leaves this environment)")
    
    # Extract features and target
    try:
        import pandas as pd
        is_dataframe = isinstance(data, pd.DataFrame)
    except:
        is_dataframe = hasattr(data, 'iloc')
    
    if is_dataframe:
        # DataFrame - convert to float64 to avoid Decimal type issues
        X = data[['age', 'variant_brca1', 'variant_tp53', 'variant_apoe4', 'bmi']].values.astype(np.float64)
        y = data['diagnosis_cancer'].values.astype(np.float64)
    else:
        # Dict (simulated)
        X = np.column_stack([data['age'], data['variant_brca1'], 
                            data['variant_tp53'], data['variant_apoe4'], data['bmi']]).astype(np.float64)
        y = np.array(data['diagnosis_cancer']).astype(np.float64)
    
    # Normalize features
    X = (X - X.mean(axis=0)) / (X.std(axis=0) + 1e-8)
    
    # Initialize weights (simple logistic regression)
    n_features = X.shape[1]
    weights = np.zeros(n_features)
    bias = 0.0
    learning_rate = 0.01
    
    # Training loop with visible progress
    log(f"   Training {EPOCHS} epochs on {len(y)} samples...")
    
    for epoch in range(EPOCHS):
        # Forward pass
        z = np.dot(X, weights) + bias
        predictions = 1 / (1 + np.exp(-np.clip(z, -500, 500)))
        
        # Compute gradients
        error = predictions - y
        weight_gradients = np.dot(X.T, error) / len(y)
        bias_gradient = np.mean(error)
        
        # Update weights
        weights -= learning_rate * weight_gradients
        bias -= learning_rate * bias_gradient
        
        # Compute loss
        loss = -np.mean(y * np.log(predictions + 1e-8) + 
                       (1 - y) * np.log(1 - predictions + 1e-8))
        
        accuracy = np.mean((predictions > 0.5) == y)
        
        log(f"   Epoch {epoch + 1}/{EPOCHS}: Loss={loss:.4f}, Accuracy={accuracy:.2%}")
        time.sleep(0.5)  # Slight delay for demo visibility
    
    log(f"✓ Training complete!")
    
    return {
        'weights': weights.tolist(),
        'bias': float(bias),
        'n_samples': len(y),
        'final_loss': float(loss),
        'final_accuracy': float(accuracy)
    }

def output_weights(model_weights, node_id, project_id):
    """Output model weights (what would be sent to the hub)."""
    weights_json = json.dumps(model_weights, indent=2)
    weights_size = len(weights_json.encode('utf-8'))
    
    log(f"")
    log(f"📤 Model weights ready to send to Federation Hub:")
    log(f"   Node: {node_id}")
    log(f"   Weights size: {weights_size} bytes")
    log(f"   Samples trained on: {model_weights['n_samples']}")
    log(f"")
    log(f"   ⚡ ONLY these {weights_size} bytes would cross the network")
    log(f"   ⚡ Patient data ({model_weights['n_samples']} records) STAYS LOCAL")
    log(f"")
    
    # Upload weights to GCS for aggregation
    gcs_bucket = os.environ.get('WEIGHTS_BUCKET', 'fedgen-weights')
    try:
        from google.cloud import storage
        client = storage.Client(project=project_id)
        bucket = client.bucket(gcs_bucket)
        blob = bucket.blob(f"weights/{node_id.lower()}_weights.json")
        blob.upload_from_string(weights_json, content_type='application/json')
        log(f"📤 Weights uploaded to gs://{gcs_bucket}/weights/{node_id.lower()}_weights.json")
    except Exception as e:
        log(f"⚠️  Could not upload to GCS: {e}")
        # Still output to stdout for local testing
        print("--- MODEL WEIGHTS ---")
        print(weights_json)
        print("--- END WEIGHTS ---")
    
    return weights_size

def main():
    # Configuration from environment
    project_id = os.environ.get('PROJECT_ID', 'fedgen-node-us')
    node_id = os.environ.get('NODE_ID', 'US')
    dataset = os.environ.get('DATASET', 'hospital_data')
    table = os.environ.get('TABLE', 'patient_genomic_data')
    
    log("=" * 60)
    log(f"🏥 FEDERATED LEARNING NODE: {node_id}")
    log(f"   Project: {project_id}")
    log(f"   Dataset: {dataset}.{table}")
    log("=" * 60)
    log("")
    
    # Step 1: Load data (stays local)
    data = load_data_from_bigquery(project_id, dataset, table)
    log("")
    
    # Step 2: Train model locally
    model_weights = train_model(data, node_id)
    log("")
    
    # Step 3: Output weights (only thing that travels)
    weights_size = output_weights(model_weights, node_id, project_id)
    
    log("=" * 60)
    log(f"✅ NODE {node_id} COMPLETE")
    log(f"   Data processed: {model_weights['n_samples']} patients")
    log(f"   Data transmitted: {weights_size} bytes (weights only)")
    log(f"   Privacy preserved: ✓")
    log("=" * 60)

if __name__ == "__main__":
    main()
