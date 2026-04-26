variable "env" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "elt-pipeline"
}

variable "bucket_arns" {
  description = "Map layer => bucket ARN (output do modulo s3-medallion)"
  type        = map(string)
}

variable "athena_results_bucket_arn" {
  description = "ARN do bucket de resultados do Athena"
  type        = string
}

variable "glue_database_names" {
  description = "Lista de nomes dos databases Glue"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
