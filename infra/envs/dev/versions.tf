terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto: bucket + dynamodb foram criados via bootstrap manual
  # (CLI), pois nao da pra criar com Terraform sem ja ter backend.
  backend "s3" {
    bucket         = "elt-pipeline-tfstate-738678807688"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "elt-pipeline-tfstate-lock"
    encrypt        = true
  }
}
