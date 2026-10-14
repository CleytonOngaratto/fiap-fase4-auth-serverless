resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpc-link"
  description = "VPC Link do API Gateway: so sai para o ALB interno, na 80."
  vpc_id      = local.vpc_id

  tags = { Name = "${local.name}-vpc-link" }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_alb" {
  security_group_id            = aws_security_group.vpc_link.id
  referenced_security_group_id = local.alb_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "Listener HTTP do ALB interno"
}

resource "aws_apigatewayv2_vpc_link" "alb" {
  name               = local.name
  subnet_ids         = local.private_subnets
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = { Name = local.name }
}
