# =============================================================================
# main.tf — Terraform provider configuration and shared locals
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ── Optional: remote state (uncomment after creating the S3 bucket) ────────
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "simpletimeservice/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-lock"
  #   encrypt        = true
  # }
}

# AWS provider — credentials are loaded from the environment or AWS CLI
# profile. Do NOT hardcode access keys here.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Locals — values derived from variables, referenced in multiple files
# -----------------------------------------------------------------------------
locals {
  name_prefix = lower("${var.project_name}-${var.environment}")

  # Availability zones in the chosen region
  azs = ["${var.aws_region}a", "${var.aws_region}b"]
}

# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------

# Grab the current AWS account ID (used to build ARNs and avoid hard-coding)
data "aws_caller_identity" "current" {}
