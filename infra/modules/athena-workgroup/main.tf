# ============================================================
# Modulo: athena-workgroup
# Cria workgroup Athena com:
#   - bytes_scanned_cutoff: mata queries que tentariam custar muito
#   - resultados criptografados SSE-S3
#   - enforce_workgroup_configuration: usuarios nao podem override
# ============================================================

resource "aws_athena_workgroup" "this" {
  name = "${var.name_prefix}-${var.env}"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${var.results_bucket}/output/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  state         = "ENABLED"
  force_destroy = true # dev only

  tags = merge(var.tags, { Component = "athena-workgroup" })
}
