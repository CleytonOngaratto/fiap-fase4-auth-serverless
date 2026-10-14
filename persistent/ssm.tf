resource "aws_ssm_parameter" "api_id" {
  name  = "/fase4/apigw/api-id"
  type  = "String"
  value = aws_apigatewayv2_api.main.id
}

resource "aws_ssm_parameter" "url" {
  name  = "/fase4/apigw/url"
  type  = "String"
  value = aws_apigatewayv2_api.main.api_endpoint
}
