terraform {

    backend "s3" {
    bucket = "backend-terraform-becompliance-prod"
    key    = "state/condepipeline-notifications.tfstate"
    region = "us-east-1"
    }

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.43.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}