terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.secrets_manager_region
  # Credentials are sourced from environment variables
}

# Configuration for the AWS Provider can be derived from several sources,
# which are applied in the following order:
#
# Parameters in the provider configuration
# Environment variables
# Shared credentials files
# Shared configuration files
# Container credentials
# Instance profile credentials and region
#
# This order matches the precedence used by the AWS CLI and the AWS SDKs.
