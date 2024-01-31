# This file is to define the variables values should be set in .tfvars or other
#------------------------------------------------------------------------------
# Labeling
variable "name_prefix" { type = string }
variable "plan_name" { type = string }
variable "owner" { type = string }

#------------------------------------------------------------------------------
# Secrets Hub Template Inputs
variable "cyberark_secrets_hub_role_arn" { type = string }
variable "secrets_manager_account"  { type = string }
variable "secrets_manager_region"  { type = string }
#------------------------------------------------------------------------------
