data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/builds/${local.name}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda"
  description = "Saida HTTPS da Lambda de auth (SSM). O acesso ao RDS vem do SG de cliente do repo 3."
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-lambda" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "SSM (chave RSA e senha do RDS) via NAT"
}

resource "aws_vpc_security_group_egress_rule" "lambda_dns_udp" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  description       = "DNS para o resolver da VPC"
}

resource "aws_vpc_security_group_egress_rule" "lambda_dns_tcp" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  description       = "DNS para o resolver da VPC (respostas truncadas)"
}

resource "aws_lambda_function" "auth" {
  function_name = local.name
  description   = "Valida CPF, confirma o cliente no RDS e assina um JWT RSA com groups=[CUSTOMER]."

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  role    = data.aws_iam_role.lambda.arn
  handler = "index.handler"
  runtime = var.lambda_runtime

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Sem reserved_concurrent_executions: a AWS exige 100 de concorrência livre e o teto do lab é 10.

  vpc_config {
    subnet_ids         = local.private_subnets
    security_group_ids = [local.rds_client_sg, aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST = local.rds_host
      DB_PORT = local.rds_port
      DB_NAME = local.rds_db_name
      DB_USER = local.rds_username
      DB_SSL  = "require"

      JWT_ISSUER      = var.jwt_issuer
      JWT_TTL_SECONDS = tostring(var.jwt_ttl_seconds)

      # Só os nomes: chave privada em env var aparece no console. A função lê os valores cifrados em runtime.
      JWT_PRIVATE_KEY_PARAM = local.jwt_private_key_param
      DB_PASSWORD_PARAM     = local.rds_password_param
    }
  }

  # Sem isto a função cria o log group antes, com retenção infinita, e o recurso acima conflita.
  depends_on = [aws_cloudwatch_log_group.lambda]
}
