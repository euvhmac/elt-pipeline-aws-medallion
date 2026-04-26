# ============================================================
# Modulo: iam-roles
# Cria 2 IAM Users (least privilege) para uso de:
#   - dbt-athena: rodar queries Athena, ler/escrever camadas Medallion
#   - lambda-slack: notificar Slack via SNS subscription
#
# Decisao: User (chave de acesso) em vez de Role assumida pois:
#   - Airflow roda LOCAL (Docker Compose), sem trust com EC2/Lambda
#   - dbt CLI roda local com profile YAML
#
# Em prod multi-conta, migrar para Role + STS AssumeRole.
# ============================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------------
# User: dbt-athena
# ----------------------------------------------------------------

resource "aws_iam_user" "dbt_athena" {
  name = "${var.name_prefix}-dbt-athena-${var.env}"
  tags = merge(var.tags, { Component = "dbt-athena-user" })
}

data "aws_iam_policy_document" "dbt_athena" {
  # Athena: rodar queries
  statement {
    sid    = "AthenaQueryExecution"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetQueryResultsStream",
      "athena:GetWorkGroup",
      "athena:StopQueryExecution",
      "athena:ListWorkGroups",
      "athena:GetDataCatalog",
      "athena:GetDatabase",
      "athena:GetTableMetadata",
      "athena:ListDatabases",
      "athena:ListTableMetadata",
    ]
    resources = ["*"]
  }

  # Glue: ler/escrever metadata das tabelas
  statement {
    sid    = "GlueCatalogReadWrite"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchUpdatePartition",
      "glue:CreatePartition",
      "glue:UpdatePartition",
      "glue:DeletePartition",
    ]
    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/*/*",
    ]
  }

  # S3 medallion: ler/escrever objetos + listar
  statement {
    sid    = "S3MedallionAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
    ]
    resources = [for arn in values(var.bucket_arns) : "${arn}/*"]
  }

  statement {
    sid    = "S3MedallionList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = values(var.bucket_arns)
  }

  # S3 athena results: leitura de output
  statement {
    sid    = "S3AthenaResults"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      var.athena_results_bucket_arn,
      "${var.athena_results_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "dbt_athena" {
  name        = "${var.name_prefix}-dbt-athena-${var.env}"
  description = "Permissoes para dbt rodar Athena + acessar S3 Medallion + Glue"
  policy      = data.aws_iam_policy_document.dbt_athena.json
  tags        = var.tags
}

resource "aws_iam_user_policy_attachment" "dbt_athena" {
  user       = aws_iam_user.dbt_athena.name
  policy_arn = aws_iam_policy.dbt_athena.arn
}

# ----------------------------------------------------------------
# Role: lambda-slack-notifier
# (Lambda assume; Sprint 6 cria a Lambda em si)
# ----------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_slack" {
  name               = "${var.name_prefix}-lambda-slack-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = merge(var.tags, { Component = "lambda-slack-role" })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_slack.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
