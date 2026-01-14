# Cloud-Native Genomics & Federation Lab

This repository houses a collection of proof-of-concept projects and reference architectures for modernizing genomic data analysis on Google Cloud. Each project has been implemented, verified, and documented.

## 📂 Projects

### 1. [Multiomics Reference Architecture](./multiomnic-ref/)
A cloud-native platform that replaces legacy HPC files with a high-speed "Data Factory," using Cloud Batch for elastic variant calling and BigQuery for population-scale SQL analytics.

### 2. [Sovereign Federated Genomic Cloud](./Federated_Genomic/)
A privacy-preserving architecture that connects multiple "Sovereign Nodes" (built on the Multiomics stack) to train global AI models without ever moving patient data across borders, ensuring GDPR/HIPAA compliance.

---

## 📖 The Narrative

Read the two-part blog series detailing the vision and implementation of these projects:

*   **[Part 1: From Files to Insights](./part_1.md)** – How we modernized the single lab (The Multiomics Project).
*   **[Part 2: Collaboration Without Compromise](./part_2.md)** – How we connected the labs globally (The Federated Project).
