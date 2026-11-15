# Contrato lido pelos outros repositórios (docs/infraestrutura/contrato.md); mudar um nome quebra quem o lê.

locals {
  parametros_publicos = {
    "rede/vpc_id"             = local.vpc_id
    "rede/cidr"               = local.cidr_vpc
    "rede/subnets_publicas"   = join(",", local.subnets_publicas)
    "rede/subnets_privadas"   = join(",", local.subnets_privadas)
    "cluster/nome"            = aws_eks_cluster.principal.name
    "cluster/sg_id"           = aws_eks_cluster.principal.vpc_config[0].cluster_security_group_id
    "nlb/dns"                 = aws_lb.api.dns_name
    "apigateway/id"           = aws_apigatewayv2_api.principal.id
    "apigateway/endpoint"     = local.url_api
    "apigateway/execucao_arn" = aws_apigatewayv2_api.principal.execution_arn
  }

  parametros_seguros = {
    "segredos/jwt_secret_key" = random_password.jwt.result
    "segredos/token_interno"  = random_password.token_interno.result
    "rabbitmq/url"            = local.rabbitmq_url
    # O SSM recusa valor vazio. "desligado" significa "sem New Relic": quem lê o parâmetro deve tratá-lo como ausência.
    "newrelic/license_key" = var.newrelic_license_key == "" ? "desligado" : var.newrelic_license_key
  }
}

resource "aws_ssm_parameter" "contrato" {
  for_each = local.parametros_publicos

  name        = "/${var.prefixo}/${each.key}"
  type        = "String"
  value       = each.value
  description = "Publicado por tech-challenge-f4-plataforma. Nao editar manualmente."

  tags = { Contrato = "plataforma" }
}

resource "aws_ssm_parameter" "segredos" {
  for_each = toset(["segredos/jwt_secret_key", "segredos/token_interno", "rabbitmq/url", "newrelic/license_key"])

  name        = "/${var.prefixo}/${each.key}"
  type        = "SecureString"
  value       = local.parametros_seguros[each.key]
  description = "Publicado por tech-challenge-f4-plataforma. Nao editar manualmente."

  tags = { Contrato = "plataforma" }
}
