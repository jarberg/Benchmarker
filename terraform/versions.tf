terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Wire up your remote state backend (S3 + DynamoDB lock) before running.
  # Commented out for LocalStack local development — uncomment for real AWS.
  # backend "s3" {
  #   bucket         = "benchmarker-terraform-state"
  #   key            = "staging/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "benchmarker-terraform-locks"
  #   encrypt        = true
  # }
}
