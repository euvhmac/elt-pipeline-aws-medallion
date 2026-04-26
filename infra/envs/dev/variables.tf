variable "env" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "elt-pipeline"
}

variable "glue_tables" {
  description = "Carregado de glue_tables.auto.tfvars.json (gerado via export_glue_schemas)."
  type = list(object({
    datamart = string
    table    = string
    columns = list(object({
      name = string
      type = string
    }))
  }))
}
