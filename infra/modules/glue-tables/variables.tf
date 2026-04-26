variable "database_name" {
  description = "Nome do Glue database onde criar as tabelas (ex: bronze_dev)."
  type        = string
}

variable "bronze_bucket" {
  description = "Nome do bucket S3 Bronze (sem s3://)."
  type        = string
}

variable "tenant_ids" {
  description = "Lista de tenants para projection enum."
  type        = list(string)
  default     = ["unit_01", "unit_02", "unit_03", "unit_04", "unit_05"]
}

variable "projection_year_min" {
  description = "Ano minimo para projection (range inclusivo)."
  type        = number
  default     = 2024
}

variable "projection_year_max" {
  description = "Ano maximo para projection (range inclusivo)."
  type        = number
  default     = 2027
}

variable "glue_tables" {
  description = "Lista de tabelas Glue. Cada item: {datamart, table, columns:[{name,type}]}."
  type = list(object({
    datamart = string
    table    = string
    columns = list(object({
      name = string
      type = string
    }))
  }))
}
