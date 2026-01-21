#!/usr/bin/env python3
"""
Federation Hub Aggregator - Combines model weights from all sovereign nodes.

This script:
1. Reads model weights from each node (from GCS or stdin)
2. Performs Federated Averaging (weighted by sample count)
3. Outputs the global model weights
"""

import os
import sys
import json
import time
import numpy as np

# Configure to use the multiomnic-ref bucket
GCS_BUCKET = os.environ.get('WEIGHTS_BUCKET', 'fedgen-weights')
PROJECT_ID = os.environ.get('PROJECT_ID', 'multiomnic-ref')
NODES = ['us', 'eu', 'sg']

def log(message):
    """Print with timestamp for demo visibility."""
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{timestamp}] {message}", flush=True)

def load_weights_from_gcs(node_id):
    """Load weights from GCS bucket."""
    try:
        from google.cloud import storage
        client = storage.Client(project=PROJECT_ID)
        bucket = client.bucket(GCS_BUCKET)
        blob = bucket.blob(f"weights/{node_id}_weights.json")
        
        if blob.exists():
            weights_json = blob.download_as_text()
            return json.loads(weights_json)
        else:
            log(f"   ⚠️  No weights found for {node_id.upper()}")
            return None
    except Exception as e:
        log(f"   ⚠️  Error loading {node_id}: {e}")
        return None

def federated_average(node_weights):
    """Perform Federated Averaging across all node weights."""
    if not node_weights:
        return None
    
    # Calculate total samples for weighted average
    total_samples = sum(w['n_samples'] for w in node_weights.values())
    
    # Initialize aggregated weights
    n_weights = len(list(node_weights.values())[0]['weights'])
    aggregated = {
        'weights': np.zeros(n_weights),
        'bias': 0.0,
        'total_samples': total_samples,
        'nodes_aggregated': list(node_weights.keys())
    }
    
    # Weighted average
    for node_id, weights in node_weights.items():
        weight_factor = weights['n_samples'] / total_samples
        aggregated['weights'] += np.array(weights['weights']) * weight_factor
        aggregated['bias'] += weights['bias'] * weight_factor
        log(f"   {node_id.upper()}: {weights['n_samples']} samples (weight: {weight_factor:.2%})")
    
    aggregated['weights'] = aggregated['weights'].tolist()
    return aggregated

def main():
    log("=" * 60)
    log("🌐 FEDERATION HUB - Weight Aggregation")
    log("   Collecting model weights from sovereign nodes...")
    log("=" * 60)
    log("")
    
    # Step 1: Load weights from each node
    log("📥 Loading weights from nodes:")
    node_weights = {}
    for node in NODES:
        log(f"   Checking {node.upper()} node...")
        weights = load_weights_from_gcs(node)
        if weights:
            node_weights[node] = weights
            log(f"   ✓ {node.upper()}: {weights['n_samples']} samples, "
                f"accuracy={weights['final_accuracy']:.2%}")
    
    log("")
    
    if not node_weights:
        log("❌ No weights found. Ensure training jobs have completed.")
        sys.exit(1)
    
    # Step 2: Perform Federated Averaging
    log("🔄 Performing Federated Averaging:")
    global_model = federated_average(node_weights)
    log("")
    
    # Step 3: Output global model
    log("=" * 60)
    log("✅ GLOBAL MODEL CREATED")
    log(f"   Nodes aggregated: {', '.join(n.upper() for n in global_model['nodes_aggregated'])}")
    log(f"   Total training samples: {global_model['total_samples']}")
    log(f"   Global weights: {len(global_model['weights'])} parameters")
    log("=" * 60)
    log("")
    log("📊 FEDERATED LEARNING BENEFITS:")
    log("   1. MODEL IMPROVEMENT (Volume):")
    log(f"      • Single Node View: ~1000 patients")
    log(f"      • Global Model View: {global_model['total_samples']} patients")
    log(f"      • Improvement: {global_model['total_samples']/1000:.1f}x more data seen")
    log("")
    log("   2. PRIVACY PRESERVATION (Data Sovereignty):")
    raw_size_est = global_model['total_samples'] * 50 * 1024 # ~50KB per genome
    weights_size = len(json.dumps(global_model))
    reduction = raw_size_est / weights_size
    
    log(f"      • Raw Data Size (kept local): ~{raw_size_est/1024/1024:.2f} MB")
    log(f"      • Transmitted Weights:        ~{weights_size} bytes")
    log(f"      • Data Reduction Factor:      {reduction:.0f}x")
    log("")
    log(f"   ⚡ The global model effectively 'learned' from all {global_model['total_samples']} patients")
    log(f"      without a single patient record leaving its country.")
    log("")
    
    # Output final model
    print("--- GLOBAL MODEL ---")
    print(json.dumps(global_model, indent=2))
    print("--- END GLOBAL MODEL ---")
    
    # Upload global model to GCS
    try:
        from google.cloud import storage
        client = storage.Client(project=PROJECT_ID)
        bucket = client.bucket(GCS_BUCKET)
        blob = bucket.blob("weights/global_model.json")
        blob.upload_from_string(json.dumps(global_model, indent=2), content_type='application/json')
        log(f"📤 Global model saved to gs://{GCS_BUCKET}/weights/global_model.json")
    except Exception as e:
        log(f"⚠️  Could not save to GCS: {e}")

if __name__ == "__main__":
    main()
