output "buckets" {
  value = module.s3_medallion.bucket_names
}

output "glue_databases" {
  value = module.glue_catalog.database_names
}

output "dbt_athena_user" {
  value = module.iam_roles.dbt_athena_user_name
}

output "athena_workgroup" {
  value = module.athena_workgroup.workgroup_name
}

output "slack_webhook_secret" {
  value = module.secrets_manager.slack_webhook_secret_name
}

output "glue_bronze_table_count" {
  value = module.glue_tables_bronze.table_count
}

output "pipeline_alerts_topic_arn" {
  value       = module.sns_lambda_slack.sns_topic_arn
  description = "Setar como PIPELINE_ALERTS_TOPIC_ARN no Airflow para ativar alertas Slack"
}

output "slack_notifier_lambda" {
  value = module.sns_lambda_slack.lambda_function_name
}
