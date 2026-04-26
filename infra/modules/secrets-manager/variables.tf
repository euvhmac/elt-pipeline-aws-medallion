variable "env" {
  type = string
}

variable "name_prefix" {
  type    = string
  default = "elt-pipeline"
}

variable "tags" {
  type    = map(string)
  default = {}
}
