# Sovereign Federated Genomic Cloud

> **Train AI on global genomic data without moving patient records across borders**

[![GCP](https://img.shields.io/badge/Google%20Cloud-4285F4?logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![TensorFlow](https://img.shields.io/badge/TensorFlow%20Federated-FF6F00?logo=tensorflow&logoColor=white)](https://www.tensorflow.org/federated)
[![License](https://img.shields.io/badge/License-Demo-blue.svg)]()

---

## Quick Start

```bash
# Run the 3-node federated learning demo
bash src/tff/demo_federated.sh
```

**Output:**
```
>> US Node (HIPAA):  1000 patients, 7.1% cancer rate
>> EU Node (GDPR):   1000 patients, 5.2% cancer rate  
>> SG Node (PDPA):   1000 patients, 10.8% cancer rate
>> Federated Result: 3000 patients, 7.7% combined rate

✓ Data NEVER left sovereign nodes
```
---
## Documentation
**Platform Overview** is recommended to read, to have understanding on what we have here. 

| Document | Description |
|----------|-------------|
| 📖 [Platform Overview](./PLATFORM_OVERVIEW.md) | Full story, constraints, production roadmap |
| 📚 [Implementation Docs](./implementation_docs/) | Phase-by-phase technical guides |
| 🔬 [Multiomnic Reference](./implementation/) | DeepVariant pipeline & BigQuery schemas |

---

## Architecture

```
            ┌─────────────────────────────────┐
            │      FEDERATION HUB (Asia)      │
            │   Model weights aggregation     │
            └─────────────────────────────────┘
                    ↑ Weights Only ↑
        ┌───────────┼───────────────┼───────────┐
        ↓           ↓               ↓           
   ┌─────────┐ ┌─────────┐ ┌─────────────────────┐
   │ US Node │ │ EU Node │ │ SG Node             │
   │ HIPAA   │ │ GDPR    │ │ PDPA + 3.49M vars   │
   └─────────┘ └─────────┘ └─────────────────────┘
```

---

## Key Features

| Feature | Implementation |
|---------|----------------|
| **Data Sovereignty** | VPC Service Controls block all egress |
| **Zero-Trust Compute** | Confidential VMs (AMD SEV) encrypt memory |
| **Federated Learning** | Only model weights exchanged, never data |
| **Real Genomics** | 3.49M DeepVariant variants included |


---

## Project Structure

```
Federated_Genomic/
├── PLATFORM_OVERVIEW.md      # Problem, solution, demo, production gaps
├── implementation_docs/      # Technical implementation guides
│   ├── 00_overview.md
│   ├── 01_infrastructure_setup.md
│   ├── 02_security_controls.md
│   ├── 03_data_layer.md
│   ├── 03a_preprocessing_pipeline.md
│   ├── 03b_deepvariant_pipeline.md
│   ├── 04_federation_engine.md
│   └── ...
├── src/
│   ├── tff/                  # Federated learning demo scripts
│   └── preprocessing/        # Batch job configurations
├── terraform/                # Infrastructure as Code
└── implementation/           # Multiomnic-ref reference architecture
```

---

## GCP Projects

| Project | Region | Role |
|---------|--------|------|
| `fedgen-node-us` | us-central1 | US Sovereign Node (HIPAA) |
| `fedgen-node-eu` | europe-west2 | EU Sovereign Node (GDPR) |
| `multiomnic-ref` | us-central1 | Singapore Research Hub + Real Variants |

---

