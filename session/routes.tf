# Sem request_parameters de propósito: o X-Trace-Id do cliente precisa atravessar intacto.
resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = local.api_id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.alb.id
  integration_uri        = local.listener_arn
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "service" {
  for_each = local.routes

  api_id    = local.api_id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}
