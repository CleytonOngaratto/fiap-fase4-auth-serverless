locals {
  name = "${var.project}-auth"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Repo      = "fiap-fase4-auth-serverless"
  }

  # nonsensitive(): o provider marca todo aws_ssm_parameter como sensitive e o plan esconderia estes valores.
  vpc_id          = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  vpc_cidr        = nonsensitive(data.aws_ssm_parameter.vpc_cidr.value)
  private_subnets = split(",", nonsensitive(data.aws_ssm_parameter.private_subnets.value))

  rds_host      = nonsensitive(data.aws_ssm_parameter.rds_endpoint.value)
  rds_port      = nonsensitive(data.aws_ssm_parameter.rds_port.value)
  rds_db_name   = nonsensitive(data.aws_ssm_parameter.rds_db_name.value)
  rds_username  = nonsensitive(data.aws_ssm_parameter.rds_username.value)
  rds_client_sg = nonsensitive(data.aws_ssm_parameter.rds_client_sg_id.value)

  lb_dns  = nonsensitive(data.aws_ssm_parameter.eks_lb_dns.value)
  app_url = "http://${local.lb_dns}"

  jwt_private_key_param = "/fase4/jwt/private-key"
  rds_password_param    = "/fase4/rds/password"
}
