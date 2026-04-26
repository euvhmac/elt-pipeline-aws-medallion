# ============================================================
# Modulo: s3-medallion
# Cria 5 buckets:
#   - bronze    (raw, versioned, IA apos N dias)
#   - silver    (cleaned)
#   - gold      (modeled, star schema)
#   - platinum  (business views)
#   - athena-results (output queries, expira apos N dias)
#
# Defaults aplicados a TODOS os buckets:
#   - Block public access
#   - SSE-S3 (AES256)
#   - Versioning (apenas Bronze + tfstate-like; demais opcional)
# ============================================================

locals {
  buckets = {
    bronze          = { versioning = true, lifecycle_ia = true, expiration = 0 }
    silver          = { versioning = false, lifecycle_ia = false, expiration = 0 }
    gold            = { versioning = false, lifecycle_ia = false, expiration = 0 }
    platinum        = { versioning = false, lifecycle_ia = false, expiration = 0 }
    athena-results  = { versioning = false, lifecycle_ia = false, expiration = var.athena_results_expiration_days }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = "${var.name_prefix}-${each.key}-${var.env}"
  tags     = merge(var.tags, { Component = "s3-${each.key}" })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in local.buckets : k => v if v.versioning }
  bucket   = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ia" {
  for_each = { for k, v in local.buckets : k => v if v.lifecycle_ia }
  bucket   = aws_s3_bucket.this[each.key].id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.bronze_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "expire" {
  for_each = { for k, v in local.buckets : k => v if v.expiration > 0 }
  bucket   = aws_s3_bucket.this[each.key].id

  rule {
    id     = "expire-old-results"
    status = "Enabled"

    filter {}

    expiration {
      days = each.value.expiration
    }
  }
}
