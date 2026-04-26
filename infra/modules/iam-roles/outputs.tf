output "dbt_athena_user_name" {
  value = aws_iam_user.dbt_athena.name
}

output "dbt_athena_user_arn" {
  value = aws_iam_user.dbt_athena.arn
}

output "dbt_athena_policy_arn" {
  value = aws_iam_policy.dbt_athena.arn
}

output "lambda_slack_role_arn" {
  value = aws_iam_role.lambda_slack.arn
}
