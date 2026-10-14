resource "aws_apigatewayv2_api" "main" {
  name          = local.name
  description   = "Borda da Fase 4. Persistente: a URL vai para o painel do Mercado Pago; as rotas vem do root session/."
  protocol_type = "HTTP"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      path                    = "$context.path"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLatency         = "$context.responseLatency"
      integrationStatus       = "$context.integration.status"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
}
