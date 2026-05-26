
terraform {
  required_version = ">= 0.12.20"
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">=3.75.2"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
