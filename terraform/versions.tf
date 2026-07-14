terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state by default so this works out of the box. For anything beyond
  # solo practice, switch to a remote backend so state isn't only on one
  # laptop and isn't at risk of concurrent-apply corruption:
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "todo-app/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}
