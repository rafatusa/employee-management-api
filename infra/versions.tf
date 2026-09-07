terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Partial backend configuration: bucket, key and region are supplied at init
  # time via -backend-config flags from the platform's state contract.
  # Backend blocks cannot reference variables, so this must stay empty.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "udap"
    }
  }
}
