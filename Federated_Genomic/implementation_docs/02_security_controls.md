# Phase 2: Security Controls

## Objective

Establish the "Data Bunker" security controls that enforce data sovereignty. This phase implements VPC Service Controls (perimeter defense) and Organization Policies (location constraints) to ensure data cannot be exfiltrated.

## Deliverables

- [x] Organization Policies enforcing resource locations
- [x] VPC Service Controls perimeters
- [x] IAM configuration with least-privilege access
- [x] Cloud KMS for customer-managed encryption keys

---

## 2.1 Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ORGANIZATION LEVEL                                │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │            Organization Policies (Hard Laws)                       │  │
│  │  • gcp.resourceLocations: Enforce regional constraints             │  │
│  │  • compute.requireConfidentialComputing: Enforce TEE              │  │
│  │  • storage.publicAccessPrevention: Block public buckets           │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │            VPC Service Controls (Perimeter Defense)                │  │
│  │                                                                    │  │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐           │  │
│  │  │ us-bunker   │    │ eu-bunker   │    │ hub-zone    │           │  │
│  │  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │           │  │
│  │  │ │BigQuery │ │    │ │BigQuery │ │    │ │Pub/Sub  │ │           │  │
│  │  │ │Storage  │ │    │ │Storage  │ │    │ │Cloud Run│ │           │  │
│  │  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │           │  │
│  │  │  DENY ALL   │    │  DENY ALL   │    │  ALLOW MSG  │           │  │
│  │  │  EGRESS     │    │  EGRESS     │    │  ONLY       │           │  │
│  │  └─────────────┘    └─────────────┘    └─────────────┘           │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## 2.2 Organization Policies

### 2.2.1 Resource Location Constraints

Enforce that resources can only be created in approved regions:

```bash
# For US Node - Only allow US locations
gcloud org-policies set-policy --project=fed-node-us <<EOF
name: projects/fed-node-us/policies/gcp.resourceLocations
spec:
  rules:
    - values:
        allowedValues:
          - in:us-locations
EOF

# For EU Node - Only allow Europe locations
gcloud org-policies set-policy --project=fed-node-eu <<EOF
name: projects/fed-node-eu/policies/gcp.resourceLocations
spec:
  rules:
    - values:
        allowedValues:
          - in:europe-locations
EOF
```

### 2.2.2 Enforce Confidential Computing

```bash
# Require confidential VMs for compute workloads
gcloud org-policies set-policy --project=fed-node-us <<EOF
name: projects/fed-node-us/policies/compute.restrictNonConfidentialComputing
spec:
  rules:
    - enforce: true
EOF
```

### 2.2.3 Block Public Access

```bash
# Prevent public bucket creation
gcloud org-policies set-policy --project=fed-node-us <<EOF
name: projects/fed-node-us/policies/storage.publicAccessPrevention
spec:
  rules:
    - enforce: true
EOF
```

### 2.2.4 Verification Test

```bash
# This MUST fail with a policy violation
gcloud storage buckets create gs://test-asia-bucket \
  --project=fed-node-us \
  --location=asia-southeast1

# Expected error:
# ERROR: Request violates constraint 'constraints/gcp.resourceLocations'
```

## 2.3 VPC Service Controls

VPC-SC creates a cryptographic perimeter that blocks data exfiltration at the API level.

### 2.3.1 Create Access Policy

```bash
# Create the access policy (org-level admin required)
gcloud access-context-manager policies create \
  --organization=$ORG_ID \
  --title="Federated Genomics Security Policy"

# Get the policy ID
export ACCESS_POLICY=$(gcloud access-context-manager policies list \
  --organization=$ORG_ID \
  --format="value(name)")
```

### 2.3.2 Create US Node Perimeter

```yaml
# us-bunker-perimeter.yaml
name: accessPolicies/${ACCESS_POLICY}/servicePerimeters/us_bunker
title: US Data Bunker
perimeterType: PERIMETER_TYPE_REGULAR
status:
  resources:
    - projects/PROJECT_NUMBER_US
  restrictedServices:
    - bigquery.googleapis.com
    - storage.googleapis.com
    - secretmanager.googleapis.com
  vpcAccessibleServices:
    enableRestriction: true
    allowedServices:
      - bigquery.googleapis.com
      - storage.googleapis.com
  ingressPolicies:
    - ingressFrom:
        sources:
          - resource: projects/PROJECT_NUMBER_HUB
        identityType: ANY_IDENTITY
      ingressTo:
        operations:
          - serviceName: pubsub.googleapis.com
            methodSelectors:
              - method: "*"
        resources:
          - "*"
  egressPolicies:
    - egressFrom:
        identityType: ANY_IDENTITY
      egressTo:
        operations:
          - serviceName: pubsub.googleapis.com
            methodSelectors:
              - method: "*"
        resources:
          - projects/PROJECT_NUMBER_HUB
```

```bash
# Apply the perimeter
gcloud access-context-manager perimeters create us-bunker \
  --policy=$ACCESS_POLICY \
  --resources=projects/$(gcloud projects describe fed-node-us --format='value(projectNumber)') \
  --restricted-services=bigquery.googleapis.com,storage.googleapis.com \
  --title="US Data Bunker"
```

### 2.3.3 Verification Test

```bash
# From Cloud Shell (outside the perimeter), try to access BigQuery
# This MUST fail
bq ls --project_id fed-node-us

# Expected error:
# Access Denied: Request is prohibited by organization's policy
```

## 2.4 IAM Configuration

### 2.4.1 Service Account Architecture

| Service Account | Project | Purpose | Key Permissions |
|-----------------|---------|---------|-----------------|
| `node-worker@fed-node-us` | US Node | Local TFF training | BigQuery Reader, Pub/Sub Publisher |
| `node-worker@fed-node-eu` | EU Node | Local TFF training | BigQuery Reader, Pub/Sub Publisher |
| `hub-orchestrator@fed-hub` | Hub | Model coordination | Pub/Sub Admin, Run Invoker |

### 2.4.2 US Node Worker SA

```bash
# Create service account
gcloud iam service-accounts create node-worker \
  --project=fed-node-us \
  --display-name="TFF Local Training Worker"

# Grant BigQuery data viewer (can query, cannot export)
gcloud projects add-iam-policy-binding fed-node-us \
  --member="serviceAccount:node-worker@fed-node-us.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

# Grant Pub/Sub publisher to Hub topic only
gcloud pubsub topics add-iam-policy-binding tff-upload \
  --project=fed-hub \
  --member="serviceAccount:node-worker@fed-node-us.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"
```

### 2.4.3 Critical: What NOT to Grant

> **⚠️ NEVER grant these roles to node workers:**
> - `roles/bigquery.dataExporter` - Allows data export
> - `roles/storage.objectCreator` - Allows writing to external buckets
> - `roles/bigquery.admin` - Full control

## 2.5 Cloud KMS (Customer-Managed Encryption)

### 2.5.1 Create Key Ring and Key

```bash
# Create key ring in the same region as data
gcloud kms keyrings create genomics-keyring \
  --project=fed-node-us \
  --location=us-central1

# Create encryption key
gcloud kms keys create patient-data-key \
  --project=fed-node-us \
  --location=us-central1 \
  --keyring=genomics-keyring \
  --purpose=encryption
```

### 2.5.2 Grant BigQuery Access to Key

```bash
# Get the BigQuery service account
BQ_SA=$(bq show --encryption_service_account --project_id=fed-node-us)

# Grant encrypter/decrypter role
gcloud kms keys add-iam-policy-binding patient-data-key \
  --project=fed-node-us \
  --location=us-central1 \
  --keyring=genomics-keyring \
  --member="serviceAccount:$BQ_SA" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

## 2.6 Security Verification Matrix

| Test | Command | Expected Result |
|------|---------|-----------------|
| Location constraint | Create bucket in wrong region | **DENIED** |
| VPC-SC perimeter | Query BQ from outside perimeter | **DENIED** |
| Data export | `bq extract` to external bucket | **DENIED** |
| Pub/Sub allowed | Publish to hub topic | **ALLOWED** |
| Internal BQ query | Query local dataset | **ALLOWED** |

## 2.7 Audit Logging Configuration

Enable Data Access logs for compliance:

```bash
gcloud projects set-iam-policy fed-node-us <<EOF
auditConfigs:
  - service: bigquery.googleapis.com
    auditLogConfigs:
      - logType: ADMIN_READ
      - logType: DATA_READ
      - logType: DATA_WRITE
  - service: storage.googleapis.com
    auditLogConfigs:
      - logType: ADMIN_READ
      - logType: DATA_READ
      - logType: DATA_WRITE
EOF
```

---

## Next Steps

→ Proceed to [03_data_layer.md](./03_data_layer.md) to set up BigQuery datasets and generate synthetic patient data.
