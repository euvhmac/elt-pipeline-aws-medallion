variable "env" {
  description = "Ambiente (dev | prd)"
  type        = string
}

variable "name_prefix" {
  description = "Prefixo dos nomes dos buckets"
  type        = string
  default     = "elt-pipeline"
}

variable "tags" {
  description = "Tags base aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}

variable "bronze_transition_to_ia_days" {
  description = "Dias antes de mover Bronze para Standard-IA (custo storage menor)"
  type        = number
  default     = 30
}

variable "athena_results_expiration_days" {
  description = "Dias antes de apagar resultados do Athena (output bucket)"
  type        = number
  default     = 7
}
