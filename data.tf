data "aws_ssm_parameter" "vpc_id" {
  name = "/fase4/vpc/id"
}

data "aws_ssm_parameter" "private_subnets" {
  name = "/fase4/vpc/private-subnets"
}

data "aws_ssm_parameter" "vpc_cidr" {
  name = "/fase4/vpc/cidr"
}

data "aws_ssm_parameter" "rds_endpoint" {
  name = "/fase4/rds/endpoint"
}

data "aws_ssm_parameter" "rds_port" {
  name = "/fase4/rds/port"
}

data "aws_ssm_parameter" "rds_db_name" {
  name = "/fase4/rds/db-name"
}

data "aws_ssm_parameter" "rds_username" {
  name = "/fase4/rds/username"
}

data "aws_ssm_parameter" "rds_client_sg_id" {
  name = "/fase4/rds/client-sg-id"
}

data "aws_ssm_parameter" "eks_lb_dns" {
  name = "/fase4/eks/lb-dns"
}

# /fase4/rds/password e /fase4/jwt/private-key não entram aqui: data source os gravaria em texto plano no state.
data "aws_iam_role" "lambda" {
  name = var.lambda_role_name
}
