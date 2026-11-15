# Internet → API Gateway → VPC Link → NLB interno → NodePort → pods.
# O NLB é do Terraform para o gateway integrar sem depender do deploy dos serviços (ADR-005).

locals {
  servicos = {
    os-service       = { node_port = 30080, porta_listener = 80 }
    execucao-service = { node_port = 30081, porta_listener = 8081 }
    billing-service  = { node_port = 30082, porta_listener = 8082 }
  }

  # Sem reescrita de caminho. POST /auth/cpf é da Lambda: a rota exata vence o {proxy+}.
  rotas = {
    "ANY /auth/{proxy+}"        = "os-service"
    "ANY /cadastro/{proxy+}"    = "os-service"
    "ANY /atendimento/{proxy+}" = "os-service"
    "GET /docs"                 = "os-service"
    "GET /openapi.json"         = "os-service"
    "GET /redoc"                = "os-service"
    "GET /health"               = "os-service"
    "ANY /catalogo/{proxy+}"    = "execucao-service"
    "ANY /estoque/{proxy+}"     = "execucao-service"
    "ANY /execucao/{proxy+}"    = "execucao-service"
    "ANY /billing/{proxy+}"     = "billing-service"
  }
}

resource "aws_lb" "api" {
  name               = "${var.prefixo}-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = local.subnets_privadas

  tags = { Name = "${var.prefixo}-nlb" }
}

resource "aws_lb_target_group" "servico" {
  for_each = local.servicos

  name        = "${var.prefixo}-${trimsuffix(each.key, "-service")}"
  port        = each.value.node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = local.vpc_id
  # Os 300 s padrão atrasam cada troca de node e o destroy; os pods já drenam pelo Kubernetes.
  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = tostring(each.value.node_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
  }
}

resource "aws_lb_listener" "servico" {
  for_each = local.servicos

  load_balancer_arn = aws_lb.api.arn
  port              = each.value.porta_listener
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.servico[each.key].arn
  }
}

resource "aws_autoscaling_attachment" "servico" {
  for_each = local.servicos

  autoscaling_group_name = aws_eks_node_group.principal.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.servico[each.key].arn
}

resource "aws_vpc_security_group_ingress_rule" "nodeports" {
  security_group_id = aws_eks_cluster.principal.vpc_config[0].cluster_security_group_id
  description       = "NodePorts dos servicos a partir do NLB interno"
  cidr_ipv4         = local.cidr_vpc
  from_port         = 30080
  to_port           = 30082
  ip_protocol       = "tcp"
}

resource "aws_security_group" "vpc_link" {
  name        = "${var.prefixo}-vpc-link"
  description = "VPC Link do API Gateway"
  vpc_id      = local.vpc_id

  tags = { Name = "${var.prefixo}-vpc-link" }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_para_nlb" {
  for_each = local.servicos

  security_group_id = aws_security_group.vpc_link.id
  description       = "Saida para o listener de ${each.key}"
  cidr_ipv4         = local.cidr_vpc
  from_port         = each.value.porta_listener
  to_port           = each.value.porta_listener
  ip_protocol       = "tcp"
}

resource "aws_apigatewayv2_vpc_link" "principal" {
  name               = "${var.prefixo}-vpc-link"
  subnet_ids         = local.subnets_privadas
  security_group_ids = [aws_security_group.vpc_link.id]
}

resource "aws_apigatewayv2_api" "principal" {
  name          = "${var.prefixo}-api"
  description   = "Porta de entrada unica da oficina mecanica"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type", "x-request-id"]
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.prefixo}"
  retention_in_days = 7
}

resource "aws_apigatewayv2_stage" "principal" {
  api_id      = aws_apigatewayv2_api.principal.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      latenciaMs     = "$context.responseLatency"
      erroIntegracao = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 50
  }
}

# No stage $default a invoke_url termina em "/"; sem o corte, quem monta "${url}/rota" gera "//rota".
locals {
  url_api = trimsuffix(aws_apigatewayv2_stage.principal.invoke_url, "/")
}

resource "aws_apigatewayv2_integration" "servico" {
  for_each = local.servicos

  api_id             = aws_apigatewayv2_api.principal.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.servico[each.key].arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.principal.id

  # O requestId vira o correlation_id da API; o IP de origem alimenta o rate limit do login.
  request_parameters = {
    "overwrite:header.x-request-id" = "$context.requestId"
    "overwrite:header.x-cliente-ip" = "$context.identity.sourceIp"
  }
}

resource "aws_apigatewayv2_route" "servico" {
  for_each = local.rotas

  api_id    = aws_apigatewayv2_api.principal.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.servico[each.value].id}"
}
