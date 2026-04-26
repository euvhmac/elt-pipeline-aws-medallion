output "sns_topic_arn" {
  description = "ARN do SNS topic pipeline-alerts (consumir no Airflow)"
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_name" {
  description = "Nome do Lambda slack-notifier"
  value       = aws_lambda_function.slack_notifier.function_name
}
