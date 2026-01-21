#!/usr/bin/env python3
"""TFF Client - Runs in sovereign node, performs local training on BigQuery data."""
import os
import json
import time
import base64
import pickle
from google.cloud import pubsub_v1, bigquery

PROJECT_ID = os.environ.get('PROJECT_ID', 'fedgen-node-us')
HUB_PROJECT = os.environ.get('HUB_PROJECT', 'fedgen-hub')
SUBSCRIPTION = os.environ.get('SUBSCRIPTION', 'sub-node-us')
NODE_ID = os.environ.get('NODE_ID', 'US')

def load_local_data():
    """Load data from local BigQuery (stays within node)."""
    print(f"Loading data from {PROJECT_ID}.hospital_data...")
    client = bigquery.Client(project=PROJECT_ID)
    query = f"""
        SELECT age, variant_brca1, variant_tp53, variant_apoe4, bmi, diagnosis_cancer
        FROM `{PROJECT_ID}.hospital_data.patient_genomic_data`
    """
    rows = list(client.query(query).result())
    X = [[r.age, r.variant_brca1, r.variant_tp53, r.variant_apoe4, r.bmi] for r in rows]
    y = [r.diagnosis_cancer for r in rows]
    print(f"Loaded {len(X)} records from local BigQuery")
    return X, y

def train_local(weights, X, y, lr=0.01):
    """Simple logistic regression training step."""
    # Simplified training for demo
    import math
    w = weights[0] if weights else [0.0] * 5
    b = weights[1] if len(weights) > 1 else 0.0
    
    for xi, yi in zip(X[:100], y[:100]):  # Mini-batch
        pred = 1 / (1 + math.exp(-sum(xij * wj for xij, wj in zip(xi, w)) - b))
        error = yi - pred
        w = [wj + lr * error * xij for wj, xij in zip(w, xi)]
        b = b + lr * error
    
    return [w, b]

def main():
    print(f"=== TFF Client starting on {NODE_ID} node ===")
    subscriber = pubsub_v1.SubscriberClient()
    publisher = pubsub_v1.PublisherClient()
    sub_path = subscriber.subscription_path(HUB_PROJECT, SUBSCRIPTION)
    topic_path = publisher.topic_path(HUB_PROJECT, 'tff-upload')
    
    X, y = load_local_data()
    
    def callback(message):
        print(f"Received model broadcast")
        data = json.loads(message.data.decode('utf-8'))
        weights = pickle.loads(base64.b64decode(data['weights']))
        
        new_weights = train_local(weights, X, y)
        
        update = {
            'node_id': NODE_ID,
            'weights': base64.b64encode(pickle.dumps(new_weights)).decode('utf-8'),
            'n_samples': len(X),
            'round': data['round']
        }
        publisher.publish(topic_path, json.dumps(update).encode('utf-8'))
        print(f"Sent update for round {data['round']} (trained on {len(X)} samples)")
        message.ack()
    
    streaming_pull_future = subscriber.subscribe(sub_path, callback)
    print(f"Listening for model broadcasts on {SUBSCRIPTION}...")
    
    try:
        streaming_pull_future.result(timeout=300)  # 5 min timeout for demo
    except Exception as e:
        streaming_pull_future.cancel()
        print(f"Client finished: {e}")

if __name__ == "__main__":
    main()
