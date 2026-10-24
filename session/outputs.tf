output "vpc_link_id" {
  description = "VPC Link que leva o Gateway até o ALB interno."
  value       = aws_apigatewayv2_vpc_link.alb.id
}

output "routes" {
  description = "Rotas publicadas no Gateway (allowlist)."
  value       = sort(tolist(local.routes))
}

output "auth_function_name" {
  description = "Função que emite o token de cliente por CPF."
  value       = aws_lambda_function.auth.function_name
}

output "os_internal_url" {
  description = "Endpoint interno que a função consulta (host do ALB interno, nunca publicado no Gateway)."
  value       = local.os_internal_url
}
