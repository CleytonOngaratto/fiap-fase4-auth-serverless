output "vpc_link_id" {
  description = "VPC Link que leva o Gateway até o ALB interno."
  value       = aws_apigatewayv2_vpc_link.alb.id
}

output "routes" {
  description = "Rotas publicadas no Gateway (allowlist)."
  value       = sort(tolist(local.routes))
}
