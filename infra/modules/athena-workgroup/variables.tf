variable "env" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "elt-pipeline"
}

variable "results_bucket" {
  description = "Nome do bucket S3 onde Athena escreve resultados"
  type        = string
}

variable "bytes_scanned_cutoff" {
  description = "Limite de bytes scaneados por query (mata query se exceder)"
  type        = number
  default     = 10737418240 # 10 GB
}

variable "tags" {
  type    = map(string)
  default = {}
}
