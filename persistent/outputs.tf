output "api_id" {
  description = "ID do HTTP API; o root session/ o lê do SSM para pendurar VPC Link, integração e rotas."
  value       = aws_apigatewayv2_api.main.id
}

output "api_endpoint" {
  description = "URL base do Gateway (stage $default, sem prefixo de stage). Estável enquanto o lab não for resetado."
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "access_log_group" {
  description = "Access log do Gateway: a prova de que uma requisição passou por ele e de qual rota casou."
  value       = aws_cloudwatch_log_group.access.name
}
