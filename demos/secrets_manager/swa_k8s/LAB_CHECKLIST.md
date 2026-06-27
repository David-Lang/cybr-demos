# Lab Spin-Up Checklist for AWS Testing

## Pre-Lab Setup (Do Before Spinning Lab)

### ✅ 1. Gather AWS Information

You'll need:

- [ ] AWS Account ID (12 digits)
- [ ] AWS Region (default: us-east-1)
- [ ] AWS Access Key ID and Secret Access Key

Record these values - you'll enter them after the lab is created:

```
AWS_ACCOUNT_ID: ___________________________
AWS_REGION: ___________________________ (default: us-east-1)
AWS_ACCESS_KEY_ID: ___________________________
AWS_SECRET_ACCESS_KEY: ___________________________
```

## Lab Instance Setup

### ✅ 1. Spin Up EC2 Lab Instance

Use your standard lab provisioning process with:
- Ubuntu 22.04 or 24.04
- IAM role attached (the one registered in Conjur)
- Sufficient disk space (20GB+)
- Security group allowing HTTPS outbound

### ✅ 2. Initial Login and Environment Check

```bash
# SSH to instance
ssh ubuntu@<instance-ip>

# Verify tenant_vars.sh is loaded
echo $TENANT_SUBDOMAIN
echo $CONJUR_ADMIN_API_KEY

# If not loaded, source it
source /opt/cybr-demos/demos/tenant_vars.sh
```

### ✅ 3. Configure Cloud Variables and Credentials

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s

# Edit cloud configuration
vi setup/cloud/vars.env
```

Fill in these values:

```bash
AWS_ACCOUNT_ID="123456789012"  # Your AWS account ID
AWS_REGION="us-east-1"         # Your AWS region
```

Save and exit (`:wq` in vi).

Next, add your AWS credentials:

```bash
# Edit AWS credentials file
vi setup/cloud/aws_credentials.env
```

Fill in your AWS credentials:

```bash
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

Save and exit (`:wq` in vi).

### ✅ 4. Run Setup

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s

# Full setup with AWS integration
bash setup.sh --aws
```

Expected runtime: 15-25 minutes

## Post-Setup Validation

### ✅ 1. Check Setup Completion

```bash
# Should see success message
# [INFO] done — run 'bash demo.sh' to explore
```

### ✅ 2. Verify Core Demo Components

```bash
# Source environment
source setup/vars.env

# Check K8s cluster
kubectl get nodes

# Check SWA components
kubectl get pods -n swa-system

# Check demo apps
kubectl get pods -n $NAMESPACE_HARDCODED
kubectl get pods -n $NAMESPACE_SWA
```

All pods should be `Running`.

### ✅ 3. Verify AWS Resources

```bash
# Check AWS outputs
cat setup/cloud/aws/aws_registered.env

# Verify S3 bucket exists
aws s3 ls s3://<bucket-name>/

# Should see test.txt
```

### ✅ 4. Verify ConfigMap

```bash
# Check ConfigMap exists
kubectl get configmap giftapp-cloud-spiffe -n $NAMESPACE_SWA

# View contents
kubectl describe configmap giftapp-cloud-spiffe -n $NAMESPACE_SWA
```

Should show `AWS_SPIFFE_ROLE_ARN`, `AWS_SPIFFE_BUCKET`, `AWS_SPIFFE_REGION`.

### ✅ 5. Test Baseline SWA Functionality

```bash
# Test healthz endpoint
kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- \
  curl -sk https://localhost:8443/healthz

# Expected response:
# {"mode":"swa","db":{...},"secrets":{"dbPassword":"present","giftappApiKey":"present"},"swaReady":true,"lastRefresh":"..."}
```

### ✅ 6. Test AWS SPIFFE Integration

```bash
# Test /csp-test endpoint
kubectl exec -n $NAMESPACE_SWA deployment/giftapp-swa -- \
  curl -sk "https://localhost:8443/csp-test?cloud=aws"

# Expected response:
# {
#   "cloud": "aws",
#   "spiffeId": "spiffe://...",
#   "audience": "sts.amazonaws.com",
#   "source": "s3://...bucket.../test.txt",
#   "content": "hello from cyberark spiffe - aws"
# }
```

## Common Issues

### Issue: AWS credentials not injected

**Symptom**: Setup fails with "AWS_ACCESS_KEY_ID is not set"

**Fix**:
1. Verify Summon is installed: `which summon`
2. Check authn-iam configuration
3. Verify safe permissions
4. Test Summon manually:
   ```bash
   cd setup/cloud/aws
   CONJUR_APPLIANCE_URL="https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud" \
   CONJUR_ACCOUNT="conjur" \
   CONJUR_AUTHN_TYPE="iam" \
   CONJUR_SERVICE_ID="aws-iam-1" \
   CONJUR_AUTHN_LOGIN="<your-login>" \
   summon --provider summon-conjur -f ./secrets.yml env | grep AWS
   ```

### Issue: ConfigMap not created

**Symptom**: `/csp-test` returns "AWS_SPIFFE_ROLE_ARN must be set"

**Fix**:
```bash
# Manually create ConfigMap
source setup/cloud/aws/aws_registered.env
kubectl create configmap giftapp-cloud-spiffe \
  --from-literal="AWS_SPIFFE_ROLE_ARN=${AWS_SPIFFE_ROLE_ARN}" \
  --from-literal="AWS_SPIFFE_BUCKET=${AWS_SPIFFE_BUCKET}" \
  --from-literal="AWS_SPIFFE_REGION=${AWS_SPIFFE_REGION}" \
  --namespace="$NAMESPACE_SWA"

kubectl rollout restart deployment/giftapp-swa -n "$NAMESPACE_SWA"
```

### Issue: STS AssumeRole fails

**Symptom**: `/csp-test` returns "sts assume role: ..." error

**Fix**:
1. Check SPIFFE ID matches IAM role trust policy:
   ```bash
   source setup/vars.env
   echo $SWA_WORKLOAD_SPIFFE_ID
   aws iam get-role --role-name "<lab-id>-swa-k8s-spiffe-role" | jq .Role.AssumeRolePolicyDocument
   ```
2. Verify OIDC provider exists:
   ```bash
   source setup/cloud/aws/aws_registered.env
   aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$AWS_SPIFFE_OIDC_ARN"
   ```

### Issue: S3 access denied

**Symptom**: `/csp-test` returns "s3 get object: 403 Forbidden"

**Fix**:
```bash
# Check IAM policy is attached
aws iam list-attached-role-policies --role-name "<lab-id>-swa-k8s-spiffe-role"

# Should show: <lab-id>-swa-k8s-spiffe-s3-policy
```

## Success Criteria

- ✅ All pods running in `swa-system`, `$NAMESPACE_HARDCODED`, `$NAMESPACE_SWA`
- ✅ `/healthz` endpoint returns `"swaReady":true`
- ✅ `/csp-test?cloud=aws` returns S3 file content
- ✅ No errors in SWA Agent or SWA Server logs
- ✅ AWS CloudTrail shows successful `AssumeRoleWithWebIdentity` calls

## Next Steps After Success

- [ ] Run `bash demo.sh` to explore the full attack-vs-defend scenario
- [ ] Review AWS CloudTrail logs for JWT-SVID authentication events
- [ ] Test `/refresh` endpoint to re-fetch secrets without pod restart
- [ ] Document any unique findings or issues for future reference

## Lab Teardown

When finished testing:

```bash
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s

# Remove AWS resources
cd setup/cloud/aws
bash remove.sh  # (if exists)

# Or manually clean up:
aws s3 rb s3://<bucket-name> --force
aws iam detach-role-policy --role-name "<role>" --policy-arn "<policy-arn>"
aws iam delete-role --role-name "<role>"
aws iam delete-policy --policy-arn "<policy-arn>"
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "<oidc-arn>"

# Remove K8s demo
cd /opt/cybr-demos/demos/secrets_manager/swa_k8s
bash remove.sh  # (if exists)

# Or reset cluster
sudo /usr/local/bin/rke2-uninstall.sh
```

## Reference

For detailed testing procedures, see: `AWS_TESTING.md`
