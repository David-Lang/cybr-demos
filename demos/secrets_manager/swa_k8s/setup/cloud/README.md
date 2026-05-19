# Cloud Provider Setup

This directory contains scripts to set up cloud provider resources for the SPIFFE JWT-SVID cloud federation demo.

## Quick Start

### 1. Configure Cloud Provider Details

Edit `vars.env` with your cloud provider information:

```bash
vi vars.env
```

Fill in the required values for the cloud(s) you want to use:

```bash
# AWS
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"

# Azure (if using)
AZURE_TENANT_ID="..."
AZURE_SUBSCRIPTION_ID="..."
AZURE_REGION="eastus"

# GCP (if using)
GCP_PROJECT_ID="..."
GCP_REGION="us-east1"
```

### 2. Add Cloud Credentials

Create credential files for each cloud provider you want to use:

#### AWS

```bash
vi aws_credentials.env
```

```bash
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

#### Azure

```bash
vi azure_credentials.env
```

```bash
AZURE_CLIENT_ID="..."
AZURE_CLIENT_SECRET="..."
```

#### GCP

```bash
vi gcp_credentials.env
```

```bash
# GCP service account JSON key
GOOGLE_APPLICATION_CREDENTIALS_JSON='{"type":"service_account","project_id":"...","private_key_id":"...",...}'
```

### 3. Run Setup

From the demo root directory:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s

# Single cloud
bash setup.sh --aws

# Multiple clouds
bash setup.sh --aws --azure --gcp
```

## What Gets Created

### AWS

- **IAM OIDC Provider**: Trusts the SWA Server OIDC endpoint
- **IAM Role**: `<lab-id>-swa-k8s-spiffe-role` with trust policy for SPIFFE JWT-SVIDs
- **IAM Policy**: `<lab-id>-swa-k8s-spiffe-s3-policy` allowing S3 read access
- **S3 Bucket**: `<lab-id>-swa-k8s-spiffe-demo` with test file
- **K8s ConfigMap**: `giftapp-cloud-spiffe` in namespace with AWS runtime config

Outputs written to: `aws/aws_registered.env`

### Azure

- Resource group
- Managed identity with federated credential
- Storage account and container
- `Storage Blob Data Reader` RBAC assignment for the managed identity
- Test blob at `spiffe-demo/test.txt`
- K8s ConfigMap with Azure runtime config

Outputs written to: `azure/azure_registered.env`

### GCP (Not Yet Tested)

- Workload identity pool
- OIDC provider
- Service account
- IAM bindings
- GCS bucket
- K8s ConfigMap with GCP credentials

Outputs written to: `gcp/gcp_registered.env`

## Security Notes

### Credential Files

The `*_credentials.env` files are **gitignored** and should never be committed to version control.

These files contain sensitive credentials and are intended for local development/testing only.

### Production Recommendations

For production deployments, consider:

- Using IAM roles for service accounts (IRSA) on EKS
- Using workload identity on GKE
- Using managed identities on AKS
- Storing credentials in a secrets management system
- Using temporary credentials with limited scope

### Cleanup

To remove cloud resources:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s/setup/cloud

# AWS cleanup
cd aws
bash remove.sh  # (if it exists)

# Or manually:
aws s3 rb s3://<bucket-name> --force
aws iam detach-role-policy --role-name "<role>" --policy-arn "<policy-arn>"
aws iam delete-role --role-name "<role>"
aws iam delete-policy --policy-arn "<policy-arn>"
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "<oidc-arn>"
```

## Files

```
cloud/
├── README.md                    # This file
├── vars.env                     # Cloud provider configuration (commit this)
├── aws_credentials.env          # AWS credentials (DO NOT COMMIT)
├── azure_credentials.env        # Azure credentials (DO NOT COMMIT)
├── gcp_credentials.env          # GCP credentials (DO NOT COMMIT)
├── aws/
│   ├── setup.sh                 # AWS resource provisioning
│   └── aws_registered.env       # Output: created resources
├── azure/
│   ├── setup.sh                 # Azure resource provisioning
│   └── azure_registered.env     # Output: created resources
└── gcp/
    ├── setup.sh                 # GCP resource provisioning
    └── gcp_registered.env       # Output: created resources
```

## Troubleshooting

### "Credentials file not found"

Make sure you created the credentials file for the cloud provider you're trying to use:

```bash
ls -la setup/cloud/*_credentials.env
```

You should see the file(s) for the clouds you want to use.

### "Access Denied" during setup

Verify your credentials have the necessary permissions:

- **AWS**: `iam:*`, `s3:*` (or more restricted policies)
- **Azure**: Contributor role on subscription
- **GCP**: Project Editor or specific IAM roles

### ConfigMap not created

The setup scripts automatically create or patch the ConfigMap without removing keys created by other cloud setup scripts. If it's missing, check:

```bash
kubectl get configmap giftapp-cloud-spiffe -n <namespace>
```

Manually create if needed:

```bash
source setup/cloud/aws/aws_registered.env
kubectl create configmap giftapp-cloud-spiffe \
  --from-literal="AWS_SPIFFE_ROLE_ARN=${AWS_SPIFFE_ROLE_ARN}" \
  --from-literal="AWS_SPIFFE_BUCKET=${AWS_SPIFFE_BUCKET}" \
  --from-literal="AWS_SPIFFE_REGION=${AWS_SPIFFE_REGION}" \
  --namespace="<namespace>"
```

For Azure:

```bash
source setup/cloud/azure/azure_registered.env
kubectl create configmap giftapp-cloud-spiffe \
  --from-literal="AZURE_SPIFFE_CLIENT_ID=${AZURE_SPIFFE_CLIENT_ID}" \
  --from-literal="AZURE_SPIFFE_TENANT_ID=${AZURE_SPIFFE_TENANT_ID}" \
  --from-literal="AZURE_SPIFFE_STORAGE_ACCOUNT=${AZURE_SPIFFE_STORAGE_ACCOUNT}" \
  --from-literal="AZURE_SPIFFE_CONTAINER=${AZURE_SPIFFE_CONTAINER}" \
  --namespace="<namespace>"
```
