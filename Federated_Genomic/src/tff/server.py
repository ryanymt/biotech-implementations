#!/usr/bin/env python3
"""TFF Server - Runs in hub, orchestrates federated training."""
import os
import json
import time
import base64
import pickle
from google.cloud import pubsub_v1

PROJECT_ID = os.environ.get('PROJECT_ID', 'fedgen-hub')
NUM_NODES = int(os.environ.get('NUM_NODES', 2))
NUM_ROUNDS = int(os.environ.get('NUM_ROUNDS', 3))

def federated_average(updates):
    """Weighted average of model weights."""
    total = sum(u['n_samples'] for u in updates)
    weights = updates[0]['weights']
    avg_w = [sum(u['weights'][0][i] * u['n_samples'] for u in updates) / total 
             for i in range(len(weights[0]))]
    avg_b = sum(u['weights'][1] * u['n_samples'] for u in updates) / total
    return [avg_w, avg_b]

def main():
    print(f"=== TFF Server starting (expecting {NUM_NODES} nodes) ===")
    publisher = pubsub_v1.PublisherClient()
    subscriber = pubsub_v1.SubscriberClient()
    broadcast_topic = publisher.topic_path(PROJECT_ID, 'tff-broadcast')
    sub_path = subscriber.subscription_path(PROJECT_ID, 'sub-hub')
    
    # Initialize model
    weights = [[0.01, 0.01, 0.01, 0.01, 0.01], 0.0]
    
    for round_num in range(1, NUM_ROUNDS + 1):
        print(f"\n=== Round {round_num}/{NUM_ROUNDS} ===")
        
        # Broadcast current weights
        msg = {'round': round_num, 'weights': base64.b64encode(pickle.dumps(weights)).decode('utf-8')}
        publisher.publish(broadcast_topic, json.dumps(msg).encode('utf-8'))
        print(f"Broadcast model to nodes")
        
        # Collect updates
        updates = []
        while len(updates) < NUM_NODES:
            response = subscriber.pull(request={'subscription': sub_path, 'max_messages': 1}, timeout=60)
            for msg in response.received_messages:
                data = json.loads(msg.message.data.decode('utf-8'))
                if data['round'] == round_num:
                    data['weights'] = pickle.loads(base64.b64decode(data['weights']))
                    updates.append(data)
                    print(f"Received update from {data['node_id']} ({data['n_samples']} samples)")
                subscriber.acknowledge(request={'subscription': sub_path, 'ack_ids': [msg.ack_id]})
        
        # Aggregate
        weights = federated_average(updates)
        print(f"Aggregated {len(updates)} updates -> new global weights")
    
    print(f"\n=== Training complete! Final weights: {weights[0][:3]}... ===")

if __name__ == "__main__":
    main()
