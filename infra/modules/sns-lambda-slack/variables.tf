variable "env" {
  type        = string
  description = "Ambiente (dev, prd)"
}

variable "name_prefix" {
  type        = string
  description = "Prefixo de naming (ex: elt-pipeline)"
}

variable "slack_secret_arn" {
  type        = string
  description = "ARN do secret no Secrets Manager contendo {webhook_url: ...}"
}

variable "lambda_source_dir" {
  type        = string
  description = "Path absoluto/relativo ao codigo Python do Lambda"
  default     = "../../../lambda/slack_notifier"
}

variable "tags" {
  type        = map(string)
  description = "Tags base"
  default     = {}
}
