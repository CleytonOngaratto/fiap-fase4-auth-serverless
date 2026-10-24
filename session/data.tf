data "aws_ssm_parameter" "api_id" {
  name = "/fase4/apigw/api-id"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/fase4/vpc/id"
}

data "aws_ssm_parameter" "vpc_cidr" {
  name = "/fase4/vpc/cidr"
}

data "aws_ssm_parameter" "private_subnets" {
  name = "/fase4/vpc/private-subnets"
}

data "aws_ssm_parameter" "alb_listener_arn" {
  name = "/fase4/alb/listener-arn"
}

data "aws_ssm_parameter" "alb_sg_id" {
  name = "/fase4/alb/sg-id"
}

data "aws_ssm_parameter" "alb_dns" {
  name = "/fase4/alb/dns"
}

# /fase4/jwt/private-key e /fase4/os/internal/service-token não entram aqui: um data source os gravaria em
# texto plano no state. A função lê os dois em runtime, por nome, com decrypt.
data "aws_iam_role" "lambda" {
  name = var.lambda_role_name
}

data "aws_caller_identity" "current" {}
