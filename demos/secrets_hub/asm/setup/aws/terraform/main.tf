locals {
  stack_name = "${var.name_prefix}-${var.secrets_manager_region}"
  policy_name = "${var.name_prefix}-${var.secrets_manager_region}"
}
resource "aws_cloudformation_stack" "sh_allow_stack" {
  # under scores are not valid in stack names use [a-zA-Z][-a-zA-Z0-9]*
  name = local.stack_name
  parameters = {
    PolicyName = local.policy_name
    CyberArkSecretsHubRoleARN = var.cyberark_secrets_hub_role_arn
    SecretsManagerAccount = var.secrets_manager_account
    SecretsManagerRegion = var.secrets_manager_region
  }
  capabilities = ["CAPABILITY_IAM"]
  template_body = file("${path.module}/SecretsHubAllowRolePolicy.json")
}

data "aws_cloudformation_stack" "sh_allow_stack" {
  name = local.stack_name
  depends_on = [aws_cloudformation_stack.sh_allow_stack]
}

data "aws_iam_roles" "sh_allow_role_search" {
  name_regex = local.stack_name
  depends_on = [aws_cloudformation_stack.sh_allow_stack]
}

output "sh_allow_role_name" {
  value =   tolist(data.aws_iam_roles.sh_allow_role_search.names)[0]
}
