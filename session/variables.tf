variable "region" {
  description = "Região AWS. O Learner Lab só libera us-east-1 e us-west-2."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo de nome e valor da tag Project."
  type        = string
  default     = "fiap-fase4"
}
