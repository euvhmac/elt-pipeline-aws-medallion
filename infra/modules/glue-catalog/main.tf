# ============================================================
# Modulo: glue-catalog
# Cria 1 database Glue por camada Medallion
# Naming: <layer>_<env>  (ex: bronze_dev, silver_dev)
# Glue databases sao gratis ate 1M objetos no catalog.
# ============================================================

resource "aws_glue_catalog_database" "this" {
  for_each    = toset(var.databases)
  name        = "${each.key}_${var.env}"
  description = "Catalog database para camada ${each.key} (${var.env})"

  # tags via aws_glue_catalog_database nao sao suportadas pelo provider
  # antes de v5.x; deixar em branco e gerenciar via default_tags do provider.
}
