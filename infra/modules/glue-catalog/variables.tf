variable "env" {
  type = string
}

variable "databases" {
  description = "Lista de databases Glue. Cada item vira <name>_<env>"
  type        = list(string)
  default     = ["bronze", "silver", "gold", "platinum", "audit"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
