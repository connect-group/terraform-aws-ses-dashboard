
terraform {
  required_version = ">= 0.12.20"
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
