output "slack_webhook_secret_arn" {
  value = aws_secretsmanager_secret.slack_webhook.arn
}

output "slack_webhook_secret_name" {
  value = aws_secretsmanager_secret.slack_webhook.name
}
