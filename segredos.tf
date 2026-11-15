# Segredos compartilhados pelos serviços; o valor chega a eles pelo SSM (ssm_contrato.tf).

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "random_password" "token_interno" {
  length  = 48
  special = false
}

resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}
