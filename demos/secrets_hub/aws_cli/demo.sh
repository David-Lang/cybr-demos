
export AWS_PROFILE=default

aws sts get-caller-identity

# --secret-id: Specifies the secret's identifier. This can be either the Amazon Resource Name (ARN) or the friendly name of the secret.
# --region: (Optional) Specifies the AWS region where the secret is stored. It's needed if your CLI configuration defaults to a different region.

secret_id="secret1_arn_or_name"
aws_region="ca-central-1"

aws secretsmanager get-secret-value --secret-id "$secret_id" --region "$aws_region"
