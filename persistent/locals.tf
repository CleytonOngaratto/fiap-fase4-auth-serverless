locals {
  name = "${var.project}-api"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Repo      = "fiap-fase4-auth-serverless"
    Root      = "persistent"
  }
}
