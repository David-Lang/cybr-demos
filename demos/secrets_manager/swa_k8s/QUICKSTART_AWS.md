# Quick Start - AWS SPIFFE Testing

This guide gets you from zero to testing AWS SPIFFE integration in ~5 minutes (after lab creation).

## Prerequisites

Have these ready before starting:
- AWS Account ID (12 digits)
- AWS Access Key ID and Secret Access Key
- AWS Region preference (default: us-east-1)

## Steps

### 1. Spin Up Lab

Create your EC2 lab instance with the standard Ubuntu setup.

### 2. SSH to Lab

```bash
ssh ubuntu@<lab-ip>
```

### 3. Configure Cloud Settings

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s

# Edit cloud configuration
vi setup/cloud/vars.env
```

Fill in:
```bash
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"
```

Save and exit.

### 4. Add AWS Credentials

```bash
# Edit credentials file
vi setup/cloud/aws_credentials.env
```

Fill in:
```bash
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

Save and exit.

### 5. Run Setup

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash setup.sh --aws
```

Expected runtime: 15-25 minutes

### 6. Test

```bash
# Source environment
source setup/vars.env

# Test the endpoint
kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- \
  curl -sk "https://localhost:8443/csp-test?cloud=aws"
```

Expected output:
```json
{
  "cloud": "aws",
  "spiffeId": "spiffe://...",
  "audience": "sts.amazonaws.com",
  "source": "s3://...bucket.../test.txt",
  "content": "hello from cyberark spiffe - aws"
}
```

## Troubleshooting

### Setup fails with "Credentials file not found"

Make sure you created and filled in `setup/cloud/aws_credentials.env`

### Test returns error instead of content

Check the error message:
- **"AWS_SPIFFE_ROLE_ARN must be set"**: ConfigMap not created
- **"fetch svid: ..."**: SWA Agent not running
- **"sts assume role: ..."**: IAM role trust policy issue
- **"s3 get object: ..."**: S3 permissions issue

See [`AWS_TESTING.md`](AWS_TESTING.md) for detailed troubleshooting.

## What Gets Created

The setup creates:
- **K8s cluster**: Single-node RKE2
- **SWA components**: Server and Agent
- **Demo apps**: giftapp-hardcoded and giftapp-swa
- **AWS resources**:
  - IAM OIDC provider
  - IAM role: `<lab-id>-swa-k8s-spiffe-role`
  - S3 bucket: `<lab-id>-swa-k8s-spiffe-demo`
  - K8s ConfigMap with AWS details

## Next Steps

After successful testing:
- Review CloudTrail logs for JWT-SVID authentication events
- Test the `/refresh` endpoint
- Run the full demo with `bash demo.sh`
- See [`AWS_TESTING.md`](AWS_TESTING.md) for advanced testing

## Files Created

Template files (pre-created, just fill in the blanks):
- `setup/cloud/vars.env` - Cloud provider configuration
- `setup/cloud/aws_credentials.env` - Your AWS credentials (**gitignored**)

Output files (generated during setup):
- `setup/cloud/aws/aws_registered.env` - Created AWS resources
- `setup/k8s/giftapp_images.env` - Built container images
- `setup/swa/swa_registered.env` - SWA trust domain details

## Security Notes

- `aws_credentials.env` is **gitignored** and never committed
- Credentials are used only during setup to create AWS resources
- Runtime authentication uses SPIFFE JWT-SVIDs (no long-lived credentials)
- Clean up AWS resources when done testing (see AWS_TESTING.md)

## Getting Help

- **Full testing guide**: [`AWS_TESTING.md`](AWS_TESTING.md)
- **Lab checklist**: [`LAB_CHECKLIST.md`](LAB_CHECKLIST.md)
- **Cloud setup details**: [`setup/cloud/README.md`](setup/cloud/README.md)
