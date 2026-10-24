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

variable "lambda_role_name" {
  description = "Role existente que a função assume. O lab não permite criar IAM: é sempre a LabRole."
  type        = string
  default     = "LabRole"
}

variable "lambda_runtime" {
  description = "Runtime da função. O cliente HTTP usa o fetch global, que existe a partir do Node 18."
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_memory_size" {
  description = "Memória em MB. Também define a fatia de CPU."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout em segundos. Maior que o timeout da chamada ao OS, para a função responder 503 em vez de ser morta."
  type        = number
  default     = 10
}

variable "os_timeout_ms" {
  description = "Timeout da chamada ao endpoint interno do OS Service."
  type        = number
  default     = 3000
}

variable "jwt_issuer" {
  description = "Issuer do token de cliente. Tem que casar com o mp.jwt.verify.issuer dos 3 serviços."
  type        = string
  default     = "https://oficina-api.com"
}

variable "jwt_ttl_seconds" {
  description = "Validade do token de cliente."
  type        = number
  default     = 3600
}

variable "jwt_private_key_param" {
  description = "Parâmetro SecureString com a chave privada RSA (bootstrap do dono)."
  type        = string
  default     = "/fase4/jwt/private-key"
}

variable "os_service_token_param" {
  description = "Parâmetro SecureString com a credencial do endpoint interno, publicado pelo terraform do os-service."
  type        = string
  default     = "/fase4/os/internal/service-token"
}

variable "log_retention_days" {
  description = "Retenção do log group da função."
  type        = number
  default     = 7
}
