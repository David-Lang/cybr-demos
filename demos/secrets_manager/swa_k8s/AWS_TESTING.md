# AWS SPIFFE JWT-SVID Testing Guide

This guide covers testing the AWS S3 integration using SPIFFE JWT-SVIDs fetched from the SWA Agent.

## Prerequisites

Before spinning up a new lab, you need:

### 1. AWS Account Configuration

- **AWS Account ID**: 12-digit account number
- **AWS Region**: Target region (default: `us-east-1`)
- **AWS Credentials**: Access key ID and secret access key with permissions to:
  - Create IAM OIDC providers
  - Create IAM roles and policies
  - Create S3 buckets
  - Upload objects to S3

## Configuration

### 1. Edit `setup/cloud/vars.env`

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
vi setup/cloud/vars.env
```

Fill in these required values:

```bash
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"
```

### 2. Edit `setup/cloud/aws_credentials.env`

```bash
vi setup/cloud/aws_credentials.env
```

Fill in your AWS credentials:

```bash
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

## Deployment

### Full Setup with AWS Integration

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash setup.sh --aws
```

This will:

1. Install all prerequisites (Docker, Terraform, RKE2, etc.)
2. Deploy RKE2 Kubernetes cluster
3. Create PAM safe and sync secrets to Conjur
4. Register SWA trust domain and install SWA Server + Agent
5. Configure Conjur JWT authenticator for SWA
6. Build and import GiftApp images
7. Deploy `giftapp-hardcoded` and `giftapp-swa`
8. **Set up AWS OIDC provider, IAM role, and S3 bucket**
9. **Create K8s ConfigMap with AWS credentials**
10. **Restart giftapp-swa to load new config**

### AWS-Only Setup (if demo already deployed)

If the base demo is already running and you just want to add AWS:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s

# Make sure aws_credentials.env is filled in
vi setup/cloud/aws_credentials.env

# Run just the AWS setup
cd setup/cloud/aws
set -a
source ../aws_credentials.env
set +a
bash setup.sh
```

## Testing

### 1. Verify AWS Resources Created

Check that the setup script created:

```bash
# Check outputs
cat setup/cloud/aws/aws_registered.env
```

Expected output:

```bash
export AWS_SPIFFE_ROLE_ARN="arn:aws:iam::123456789012:role/<lab-id>-swa-k8s-spiffe-role"
export AWS_SPIFFE_BUCKET="<lab-id>-swa-k8s-spiffe-demo"
export AWS_SPIFFE_REGION="us-east-1"
export AWS_SPIFFE_OIDC_ARN="arn:aws:iam::123456789012:oidc-provider/<spiffe-server-host>"
```

Verify in AWS Console or CLI:

```bash
# Check IAM OIDC provider
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "<oidc-arn>"

# Check IAM role
aws iam get-role --role-name "<lab-id>-swa-k8s-spiffe-role"

# Check S3 bucket
aws s3 ls s3://<bucket-name>/
```

### 2. Verify K8s ConfigMap

```bash
# Get namespace
source setup/vars.env
echo $NAMESPACE_SWA

# Check ConfigMap exists
kubectl get configmap giftapp-cloud-spiffe -n $NAMESPACE_SWA

# View ConfigMap contents
kubectl describe configmap giftapp-cloud-spiffe -n $NAMESPACE_SWA
```

Expected contents:

```
Data
====
AWS_SPIFFE_ROLE_ARN:
----
arn:aws:iam::123456789012:role/<lab-id>-swa-k8s-spiffe-role

AWS_SPIFFE_BUCKET:
----
<lab-id>-swa-k8s-spiffe-demo

AWS_SPIFFE_REGION:
----
us-east-1
```

### 3. Verify giftapp-swa Pod Environment

```bash
# Find giftapp-swa pod
kubectl get pods -n $NAMESPACE_SWA -l app=giftapp-swa

# Check environment variables
kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- env | grep AWS_SPIFFE
```

Expected output:

```
AWS_SPIFFE_ROLE_ARN=arn:aws:iam::123456789012:role/...
AWS_SPIFFE_BUCKET=...
AWS_SPIFFE_REGION=us-east-1
```

### 4. Test /csp-test Endpoint

```bash
# Direct pod test
kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- \
  curl -sk "https://localhost:8443/csp-test?cloud=aws"
```

Expected successful response:

```json
{
  "cloud": "aws",
  "spiffeId": "spiffe://<trust-domain>/<node-group>/workload/<namespace>/giftapp-swa-sa",
  "audience": "sts.amazonaws.com",
  "source": "s3://<bucket>/test.txt",
  "content": "hello from cyberark spiffe - aws"
}
```

Error responses will include an `"error"` field instead of `"content"`.

### 5. Test Flow End-to-End

The complete flow is:

```
1. giftapp-swa → /csp-test?cloud=aws
2. → fetchSVID(audience="sts.amazonaws.com")
3. → SWA Agent socket → JWT-SVID
4. → AWS STS AssumeRoleWithWebIdentity
5. → temporary AWS credentials
6. → S3 GetObject with SigV4 signing (no AWS SDK!)
7. → return test.txt content
```

### 6. Verify SWA Agent Logs

```bash
# Check SWA Agent logs for JWT-SVID issuance
kubectl logs -n swa-system daemonset/swa-agent --tail=50 | grep -i jwt
```

Look for JWT-SVID fetch with audience `sts.amazonaws.com`.

## Troubleshooting

### ConfigMap Not Found

If `giftapp-cloud-spiffe` ConfigMap is missing:

```bash
# Manually create from aws_registered.env
source setup/cloud/aws/aws_registered.env
kubectl create configmap giftapp-cloud-spiffe \
  --from-literal="AWS_SPIFFE_ROLE_ARN=${AWS_SPIFFE_ROLE_ARN}" \
  --from-literal="AWS_SPIFFE_BUCKET=${AWS_SPIFFE_BUCKET}" \
  --from-literal="AWS_SPIFFE_REGION=${AWS_SPIFFE_REGION}" \
  --namespace="$NAMESPACE_SWA"

# Restart deployment
kubectl rollout restart deployment/giftapp-swa -n "$NAMESPACE_SWA"
```

### Environment Variables Not Loading

Verify ConfigMap is mounted:

```bash
kubectl get deployment giftapp-swa -n $NAMESPACE_SWA -o yaml | grep -A5 envFrom
```

Should show:

```yaml
envFrom:
- configMapRef:
    name: giftapp-swa-config
- configMapRef:
    name: giftapp-cloud-spiffe
    optional: true
```

### STS AssumeRole Failures

Common causes:

1. **OIDC provider thumbprint mismatch**: Re-run `setup/cloud/aws/setup.sh`
2. **IAM role trust policy mismatch**: Check `sub` claim matches `SWA_WORKLOAD_SPIFFE_ID`
3. **JWT-SVID audience wrong**: Should be `sts.amazonaws.com`

Check CloudTrail for detailed error:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 5
```

### S3 Access Denied

Verify IAM policy is attached:

```bash
aws iam list-attached-role-policies \
  --role-name "<lab-id>-swa-k8s-spiffe-role"
```

Test S3 access with AWS CLI:

```bash
source setup/cloud/aws/aws_registered.env
aws s3 ls s3://${AWS_SPIFFE_BUCKET}/
```

### Image Rebuild Needed

If you modified the Go code:

```bash
# Rebuild with no cache
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash setup/k8s/build_giftapp_images.sh

# Restart pods
kubectl rollout restart deployment/giftapp-swa -n "$NAMESPACE_SWA"
```

## Architecture

### JWT-SVID Flow

```
┌─────────────────┐
│  giftapp-swa    │
│   container     │
└────────┬────────┘
         │ 1. Fetch JWT-SVID (audience=sts.amazonaws.com)
         │
         v
┌─────────────────┐
│   SWA Agent     │  2. Attest workload identity
│   DaemonSet     │     (K8s namespace + service account)
└────────┬────────┘
         │ 3. Issue JWT-SVID signed by SWA Server
         │
         v
┌─────────────────┐
│   SWA Server    │  4. Sign JWT with trust domain key
│   StatefulSet   │
└─────────────────┘
```

### AWS Authentication Flow

```
┌─────────────────┐
│  giftapp-swa    │  1. JWT-SVID with audience=sts.amazonaws.com
└────────┬────────┘
         │
         v
┌─────────────────┐
│   AWS STS       │  2. Validate JWT signature via OIDC discovery
│                 │  3. Check JWT claims match IAM role trust policy
└────────┬────────┘
         │ 4. Return temporary AWS credentials
         │
         v
┌─────────────────┐
│   Amazon S3     │  5. Access S3 with SigV4-signed request
│                 │     (no AWS SDK - pure stdlib!)
└─────────────────┘
```

### No AWS SDK!

The implementation uses **pure Go stdlib** - no AWS SDK dependency:

- Manual STS XML parsing
- Manual SigV4 signature generation
- Direct HTTPS calls to AWS APIs

This demonstrates the universality of SPIFFE JWT-SVIDs as a credential format.

## Next Steps

After successful AWS testing:

- Add Azure blob storage testing with `--azure` flag
- Add GCP cloud storage testing with `--gcp` flag
- Test multi-cloud: `bash setup.sh --aws --azure --gcp`
- Update demo.sh walkthrough to showcase cloud federation

## Reference

- **AWS IAM OIDC**: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
- **SPIFFE JWT-SVID**: https://github.com/spiffe/spiffe/blob/main/standards/JWT-SVID.md
- **AWS SigV4**: https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
