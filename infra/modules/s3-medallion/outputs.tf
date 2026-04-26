output "bucket_names" {
  description = "Map de layer => bucket name"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "Map de layer => bucket ARN"
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "bronze_bucket" {
  value = aws_s3_bucket.this["bronze"].id
}

output "silver_bucket" {
  value = aws_s3_bucket.this["silver"].id
}

output "gold_bucket" {
  value = aws_s3_bucket.this["gold"].id
}

output "platinum_bucket" {
  value = aws_s3_bucket.this["platinum"].id
}

output "athena_results_bucket" {
  value = aws_s3_bucket.this["athena-results"].id
}
