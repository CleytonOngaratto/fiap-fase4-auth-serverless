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

variable "log_retention_days" {
  description = "Retenção do access log do Gateway, em dias."
  type        = number
  default     = 7
}
