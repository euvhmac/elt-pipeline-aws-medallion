# ============================================================
# Modulo: glue-tables
# Cria 1 aws_glue_catalog_table por (datamart, table) na database Bronze
# usando Athena Partition Projection (sem precisar registrar particoes)
#
# Particoes virtuais: tenant_id, year, month, day
# Storage: Parquet snappy em s3://<bucket>/<datamart>/<table>/
# ============================================================

locals {
  # Map normalizado: chave "<datamart>__<table>" -> objeto
  tables_map = {
    for t in var.glue_tables :
    "${t.datamart}__${t.table}" => t
  }
}

resource "aws_glue_catalog_table" "this" {
  for_each = local.tables_map

  database_name = var.database_name
  name          = each.value.table

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"      = "parquet"
    "EXTERNAL"            = "TRUE"
    "parquet.compression" = "SNAPPY"
    "has_encrypted_data"  = "false"
    "datamart"            = each.value.datamart

    # === Athena Partition Projection ===
    "projection.enabled"          = "true"
    "projection.tenant_id.type"   = "enum"
    "projection.tenant_id.values" = join(",", var.tenant_ids)
    "projection.year.type"        = "integer"
    "projection.year.range"       = "${var.projection_year_min},${var.projection_year_max}"
    "projection.month.type"       = "integer"
    "projection.month.range"      = "1,12"
    "projection.month.digits"     = "2"
    "projection.day.type"         = "integer"
    "projection.day.range"        = "1,31"
    "projection.day.digits"       = "2"
    "storage.location.template"   = "s3://${var.bronze_bucket}/${each.value.datamart}/${each.value.table}/tenant_id=$${tenant_id}/year=$${year}/month=$${month}/day=$${day}/"
  }

  # Particoes virtuais (Hive). Nao registramos valores; a projection cuida.
  partition_keys {
    name = "tenant_id"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }

  storage_descriptor {
    location      = "s3://${var.bronze_bucket}/${each.value.datamart}/${each.value.table}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    dynamic "columns" {
      for_each = each.value.columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}
