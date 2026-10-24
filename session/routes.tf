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

resource "aws_apigatewayv2_integration" "auth" {
  api_id                 = local.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = local.api_id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${local.api_id}/*/*"
}
