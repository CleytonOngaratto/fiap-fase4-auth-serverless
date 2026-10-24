locals {
  name = "${var.project}-edge"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Repo      = "fiap-fase4-auth-serverless"
    Root      = "session"
  }

  api_id          = nonsensitive(data.aws_ssm_parameter.api_id.value)
  vpc_id          = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  vpc_cidr        = nonsensitive(data.aws_ssm_parameter.vpc_cidr.value)
  private_subnets = split(",", nonsensitive(data.aws_ssm_parameter.private_subnets.value))
  listener_arn    = nonsensitive(data.aws_ssm_parameter.alb_listener_arn.value)
  alb_sg_id       = nonsensitive(data.aws_ssm_parameter.alb_sg_id.value)
  alb_dns         = nonsensitive(data.aws_ssm_parameter.alb_dns.value)

  os_internal_url = "http://${local.alb_dns}/carworkshop/v1/internal/customers"

  # Allowlist: o casamento é sensível a caixa, uma rota genérica exporia /q/* e rota sem integração não bloqueia nada.
  routes = toset([
    "POST /carworkshop/v1/auth/login",
    "ANY /carworkshop/v1/customers/{proxy+}",
    "ANY /carworkshop/v1/vehicles/{proxy+}",
    "ANY /carworkshop/v1/service",
    "ANY /carworkshop/v1/service/{proxy+}",
    "ANY /carworkshop/v1/parts-and-supplies",
    "ANY /carworkshop/v1/parts-and-supplies/{proxy+}",
    "ANY /carworkshop/v1/work-orders",
    "ANY /carworkshop/v1/work-orders/{proxy+}",
    "GET /carworkshop/v1/branches",
    "GET /carworkshop/v1/tracking/{id}",
    "GET /billing/v1/info",
    "GET /execution/v1/info",
  ])
}
