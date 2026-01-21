# Phase 4: Federation Engine

## Objective

Build the core Federated Learning infrastructure using TensorFlow Federated (TFF), with Pub/Sub as the communication fabric between sovereign nodes and the central hub.

## Deliverables

- [x] Pub/Sub topics and subscriptions
- [x] TFF Client code (local trainer)
- [x] TFF Server code (aggregator)
- [x] Docker containers for deployment

---

## 4.1 Communication Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FEDERATION HUB                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │   tff-broadcast (Topic)          tff-upload (Topic)          │   │
│  │   ├── sub-node-us                └── sub-hub                 │   │
│  │   └── sub-node-eu                                            │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
       │ Broadcast Model                      ▲ Receive Updates
       ▼                                      │
┌──────────────────┐              ┌──────────────────┐
│    US Node       │              │    EU Node       │
│  TFF Client      │──────────────│  TFF Client      │
│  Local Training  │   Parallel   │  Local Training  │
└──────────────────┘              └──────────────────┘
```

## 4.2 Create Pub/Sub Resources

```bash
PROJECT_HUB="fed-hub"

# Create topics
gcloud pubsub topics create tff-broadcast --project=$PROJECT_HUB
gcloud pubsub topics create tff-upload --project=$PROJECT_HUB

# Create subscriptions
gcloud pubsub subscriptions create sub-node-us \
  --topic=tff-broadcast --project=$PROJECT_HUB
gcloud pubsub subscriptions create sub-node-eu \
  --topic=tff-broadcast --project=$PROJECT_HUB
gcloud pubsub subscriptions create sub-hub \
  --topic=tff-upload --project=$PROJECT_HUB

# Grant node workers publisher access
gcloud pubsub topics add-iam-policy-binding tff-upload --project=$PROJECT_HUB \
  --member="serviceAccount:node-worker@fed-node-us.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"
gcloud pubsub topics add-iam-policy-binding tff-upload --project=$PROJECT_HUB \
  --member="serviceAccount:node-worker@fed-node-eu.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"
```

## 4.3 TFF Client Code

Create `src/tff/client.py`:

```python
#!/usr/bin/env python3
"""TFF Client - Runs in sovereign node, performs local training."""

import os
import json
import pickle
import base64
from google.cloud import pubsub_v1, bigquery
import numpy as np
import tensorflow as tf

PROJECT_ID = os.environ['PROJECT_ID']
HUB_PROJECT = os.environ['HUB_PROJECT']
SUBSCRIPTION = os.environ['SUBSCRIPTION']
NODE_ID = os.environ['NODE_ID']

def load_local_data():
    """Load data from local BigQuery (stays within node)."""
    client = bigquery.Client(project=PROJECT_ID)
    query = """
        SELECT age, variant_brca1, variant_tp53, variant_apoe4, bmi, diagnosis_cancer
        FROM `{}.hospital_data.patient_genomic_data`
    """.format(PROJECT_ID)
    df = client.query(query).to_dataframe()
    X = df[['age', 'variant_brca1', 'variant_tp53', 'variant_apoe4', 'bmi']].values
    y = df['diagnosis_cancer'].values
    return X, y

def create_model():
    """Create simple logistic regression model."""
    model = tf.keras.Sequential([
        tf.keras.layers.Dense(1, activation='sigmoid', input_shape=(5,))
    ])
    model.compile(optimizer='sgd', loss='binary_crossentropy', metrics=['accuracy'])
    return model

def train_local(model, X, y, epochs=1):
    """Train model on local data."""
    model.fit(X, y, epochs=epochs, batch_size=32, verbose=0)
    return model.get_weights(), len(X)

def serialize_weights(weights):
    """Serialize model weights to base64."""
    return base64.b64encode(pickle.dumps(weights)).decode('utf-8')

def deserialize_weights(data):
    """Deserialize weights from base64."""
    return pickle.loads(base64.b64decode(data.encode('utf-8')))

def main():
    subscriber = pubsub_v1.SubscriberClient()
    publisher = pubsub_v1.PublisherClient()
    sub_path = subscriber.subscription_path(HUB_PROJECT, SUBSCRIPTION)
    topic_path = publisher.topic_path(HUB_PROJECT, 'tff-upload')
    
    X, y = load_local_data()
    print(f"Loaded {len(X)} local records")
    
    def callback(message):
        print(f"Received model from hub")
        data = json.loads(message.data.decode('utf-8'))
        weights = deserialize_weights(data['weights'])
        
        model = create_model()
        model.set_weights(weights)
        
        new_weights, n_samples = train_local(model, X, y)
        
        update = {
            'node_id': NODE_ID,
            'weights': serialize_weights(new_weights),
            'n_samples': n_samples,
            'round': data['round']
        }
        publisher.publish(topic_path, json.dumps(update).encode('utf-8'))
        print(f"Sent update for round {data['round']}")
        message.ack()
    
    future = subscriber.subscribe(sub_path, callback)
    print(f"Listening for model broadcasts...")
    future.result()

if __name__ == "__main__":
    main()
```

## 4.4 TFF Server Code

Create `src/tff/server.py`:

```python
#!/usr/bin/env python3
"""TFF Server - Runs in hub, orchestrates federated training."""

import os
import json
import time
from google.cloud import pubsub_v1
import numpy as np
import tensorflow as tf

PROJECT_ID = os.environ['PROJECT_ID']
NUM_NODES = int(os.environ.get('NUM_NODES', 2))
NUM_ROUNDS = int(os.environ.get('NUM_ROUNDS', 10))

# Reuse serialize/deserialize from client
from client import serialize_weights, deserialize_weights, create_model

def federated_average(updates):
    """Weighted average of model weights."""
    total_samples = sum(u['n_samples'] for u in updates)
    avg_weights = []
    for i in range(len(updates[0]['weights'])):
        weighted = sum(u['weights'][i] * u['n_samples'] for u in updates)
        avg_weights.append(weighted / total_samples)
    return avg_weights

def main():
    publisher = pubsub_v1.PublisherClient()
    subscriber = pubsub_v1.SubscriberClient()
    broadcast_topic = publisher.topic_path(PROJECT_ID, 'tff-broadcast')
    sub_path = subscriber.subscription_path(PROJECT_ID, 'sub-hub')
    
    model = create_model()
    
    for round_num in range(1, NUM_ROUNDS + 1):
        print(f"\n=== Round {round_num} ===")
        
        # Broadcast current weights
        message = {
            'round': round_num,
            'weights': serialize_weights(model.get_weights())
        }
        publisher.publish(broadcast_topic, json.dumps(message).encode('utf-8'))
        print(f"Broadcast model to nodes")
        
        # Collect updates
        updates = []
        while len(updates) < NUM_NODES:
            response = subscriber.pull(sub_path, max_messages=1, timeout=60)
            for msg in response.received_messages:
                data = json.loads(msg.message.data.decode('utf-8'))
                if data['round'] == round_num:
                    data['weights'] = deserialize_weights(data['weights'])
                    updates.append(data)
                    print(f"Received update from {data['node_id']}")
                subscriber.acknowledge(sub_path, [msg.ack_id])
        
        # Aggregate
        new_weights = federated_average(updates)
        model.set_weights(new_weights)
        print(f"Aggregated {len(updates)} updates")
    
    model.save('global_model.keras')
    print("\nTraining complete!")

if __name__ == "__main__":
    main()
```

## 4.5 Dockerfile

```dockerfile
FROM python:3.10-slim
WORKDIR /app
RUN pip install google-cloud-pubsub google-cloud-bigquery tensorflow numpy pandas
COPY src/tff/ .
ENV PYTHONUNBUFFERED=1
```

## 4.6 Build and Push Containers

```bash
# Configure Artifact Registry
gcloud artifacts repositories create tff-images \
  --repository-format=docker \
  --location=us-central1 \
  --project=fed-hub

# Build and push
docker build -t us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1 .
docker push us-central1-docker.pkg.dev/fed-hub/tff-images/tff-worker:v1
```

---

→ Proceed to [05_compute_layer.md](./05_compute_layer.md)
