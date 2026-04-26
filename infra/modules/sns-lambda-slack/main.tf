# ============================================================
# Modulo: sns-lambda-slack
# SNS topic + Lambda notifier que posta em Slack via webhook
# armazenado no Secrets Manager.
#
# Custo: SNS $0.50/1M publish, Lambda free tier (1M invocacoes/mes),
# ~$0/mes em volume de dev.
# ============================================================

# ----------------------------------------------------------------------
# SNS topic
# ----------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-pipeline-alerts-${var.env}"
  tags = merge(var.tags, { Component = "sns-alerts" })
}

# ----------------------------------------------------------------------
# Lambda package (zip do diretorio fonte)
# ----------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/slack_notifier.zip"
}

# ----------------------------------------------------------------------
# IAM role + policies para Lambda
# ----------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-slack-notifier-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = merge(var.tags, { Component = "iam-lambda-slack" })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_secret_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.slack_secret_arn]
  }
}

resource "aws_iam_role_policy" "lambda_secret_read" {
  name   = "read-slack-secret"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_secret_read.json
}

# ----------------------------------------------------------------------
# Lambda function
# ----------------------------------------------------------------------
resource "aws_lambda_function" "slack_notifier" {
  function_name    = "${var.name_prefix}-slack-notifier-${var.env}"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.11"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      SLACK_SECRET_ARN = var.slack_secret_arn
    }
  }

  tags = merge(var.tags, { Component = "lambda-slack-notifier" })
}

# ----------------------------------------------------------------------
# SNS -> Lambda subscription
# ----------------------------------------------------------------------
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}
