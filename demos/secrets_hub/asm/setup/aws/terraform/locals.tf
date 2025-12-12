locals {
  name_prefix = terraform.workspace

  # Common tags to be assigned to all resources
  common_tags = {
    Owner          = var.owner
    Purpose        = "cybr-poc"
    Terraform      = "true"
    Workspace      = terraform.workspace
    Plan           = var.plan_name
    # To prevent installing the SSM Agent
    CA_iSSMExclude = "YES"
    # To prevent installing the Trend Micro Agent
    CA_iTMExclude = "YES"
    CA_iTMExcludeReason = "POV Test"
    # To prevent stopped instance auto deletion
    CA_iEC2Retain = "active"
  }
}
