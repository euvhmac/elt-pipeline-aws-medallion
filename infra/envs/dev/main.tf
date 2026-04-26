# ============================================================
# Env: dev
# Compoe os modulos s3-medallion + glue-catalog + iam-roles
# + secrets-manager + athena-workgroup
# ============================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "elt-pipeline-aws-medallion"
      Environment = var.env
      ManagedBy   = "Terraform"
      Owner       = "vhmac"
    }
  }
}

locals {
  base_tags = {
    Project     = "elt-pipeline-aws-medallion"
    Environment = var.env
    ManagedBy   = "Terraform"
    Owner       = "vhmac"
  }
}

module "s3_medallion" {
  source      = "../../modules/s3-medallion"
  env         = var.env
  name_prefix = var.name_prefix
  tags        = local.base_tags
}

module "glue_catalog" {
  source = "../../modules/glue-catalog"
  env    = var.env
  tags   = local.base_tags
}

module "iam_roles" {
  source                    = "../../modules/iam-roles"
  env                       = var.env
  name_prefix               = var.name_prefix
  bucket_arns               = module.s3_medallion.bucket_arns
  athena_results_bucket_arn = module.s3_medallion.bucket_arns["athena-results"]
  glue_database_names       = values(module.glue_catalog.database_names)
  tags                      = local.base_tags
}

module "secrets_manager" {
  source      = "../../modules/secrets-manager"
  env         = var.env
  name_prefix = var.name_prefix
  tags        = local.base_tags
}

module "athena_workgroup" {
  source         = "../../modules/athena-workgroup"
  env            = var.env
  name_prefix    = var.name_prefix
  results_bucket = module.s3_medallion.athena_results_bucket
  tags           = local.base_tags
}

module "glue_tables_bronze" {
  source        = "../../modules/glue-tables"
  database_name = module.glue_catalog.database_names["bronze"]
  bronze_bucket = module.s3_medallion.bronze_bucket
  glue_tables   = var.glue_tables
}

module "sns_lambda_slack" {
  source           = "../../modules/sns-lambda-slack"
  env              = var.env
  name_prefix      = var.name_prefix
  slack_secret_arn = module.secrets_manager.slack_webhook_secret_arn
  tags             = local.base_tags
}
