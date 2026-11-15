# Dashboards, alertas, monitor de uptime e métricas da Lambda no New Relic (ADR-014).
locals {
  newrelic_ativo = nonsensitive(var.newrelic_api_key != "") && var.newrelic_account_id != ""
  # A integração AWS exige uma role própria, que o laboratório não permite criar.
  newrelic_aws = local.newrelic_ativo && !local.laboratorio
  email_ativo  = local.newrelic_ativo && var.email_alertas != ""
  monitor      = "${var.prefixo}-api-health"
  logs_os      = "FROM Log WHERE evento = 'os_status'"
  logs_saga    = "FROM Log WHERE evento = 'saga'"
  namespaces   = "('os-service', 'execucao-service', 'billing-service', 'mensageria')"
  app          = "FROM Transaction WHERE appName LIKE '${var.prefixo}-%'"
  pods         = "FROM K8sContainerSample WHERE clusterName = '${var.newrelic_cluster_name}' AND namespaceName IN ${local.namespaces}"
  # Eventos de consumo fora do caminho feliz, logados pelos três serviços.
  mensagens_anormais = "('mensagem_repetida', 'saga_evento_descartado', 'mensagem_invalida', 'mensagem_sem_saga', 'falha_no_consumo', 'publicacao_recusada')"

  alertas = {
    falha_os = {
      nome     = "Falha no processamento de ordens de serviço"
      consulta = "SELECT filter(count(*), WHERE http_status >= 500 OR level = 'ERROR') FROM Log WHERE logger = 'oficina.http' AND http_path LIKE '/atendimento/os%'"
      janela   = 60
    }
    saga_sem_compensacao = {
      nome     = "Saga parada em falha na compensação"
      consulta = "SELECT filter(count(*), WHERE estado = 'FALHA_NA_COMPENSACAO') FROM Log WHERE evento = 'saga'"
      janela   = 60
    }
    falha_no_consumo = {
      nome     = "Falha ao processar mensagens da Saga"
      consulta = "SELECT filter(count(*), WHERE evento IN ('falha_no_consumo', 'mensagem_sem_saga', 'mensagem_invalida')) FROM Log WHERE logger = 'oficina.mensageria'"
      janela   = 300
    }
    api_fora_do_ar = {
      nome     = "API fora do ar para o monitor externo"
      consulta = "SELECT filter(count(*), WHERE result != 'SUCCESS') FROM SyntheticCheck WHERE monitorName = '${local.monitor}'"
      janela   = 300
    }
  }
}

resource "newrelic_one_dashboard" "oficina" {
  count = local.newrelic_ativo ? 1 : 0
  name  = "Tech Challenge · Oficina"

  page {
    name = "Saga"

    widget_billboard {
      title  = "Sagas iniciadas (24h)"
      row    = 1
      column = 1
      width  = 3
      nrql_query {
        query = "SELECT uniqueCount(saga_id) ${local.logs_saga} AND gatilho = 'OSAberta' SINCE 1 day ago"
      }
    }

    widget_billboard {
      title  = "Concluídas (24h)"
      row    = 1
      column = 4
      width  = 3
      nrql_query {
        query = "SELECT uniqueCount(saga_id) ${local.logs_saga} AND estado = 'CONCLUIDA' SINCE 1 day ago"
      }
    }

    widget_billboard {
      title  = "Compensadas (24h)"
      row    = 1
      column = 7
      width  = 3
      nrql_query {
        query = "SELECT uniqueCount(saga_id) ${local.logs_saga} AND estado = 'COMPENSADA' SINCE 1 day ago"
      }
    }

    widget_billboard {
      title  = "Falha na compensação (24h)"
      row    = 1
      column = 10
      width  = 3
      nrql_query {
        query = "SELECT uniqueCount(saga_id) ${local.logs_saga} AND estado = 'FALHA_NA_COMPENSACAO' SINCE 1 day ago"
      }
    }

    widget_pie {
      title  = "Sagas desfeitas por motivo"
      row    = 4
      column = 1
      width  = 4
      nrql_query {
        query = "SELECT uniqueCount(saga_id) ${local.logs_saga} AND estado = 'COMPENSADA' FACET motivo SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Passos da Saga por gatilho"
      row    = 4
      column = 5
      width  = 8
      nrql_query {
        query = "SELECT count(*) ${local.logs_saga} FACET gatilho TIMESERIES"
      }
    }

    widget_bar {
      title  = "Comandos atendidos pela Execução e pelo Billing"
      row    = 7
      column = 1
      width  = 6
      nrql_query {
        query = "SELECT count(*) FROM Log WHERE evento = 'comando_processado' FACET tipo SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Mensagens repetidas, descartadas ou com falha"
      row    = 7
      column = 7
      width  = 6
      nrql_query {
        query = "SELECT count(*) FROM Log WHERE evento IN ${local.mensagens_anormais} FACET evento TIMESERIES"
      }
    }

    widget_line {
      title  = "Consumo de mensagens por serviço (rastreamento distribuído)"
      row    = 10
      column = 1
      width  = 6
      nrql_query {
        query = "SELECT count(*) FROM Transaction WHERE appName LIKE '${var.prefixo}-%' AND name LIKE 'OtherTransaction/Message/RabbitMQ/%' FACET appName TIMESERIES"
      }
    }

    widget_table {
      title  = "Linha do tempo das Sagas"
      row    = 10
      column = 7
      width  = 6
      nrql_query {
        query = "SELECT saga_id, os_id, gatilho, passo, estado, motivo, comandos ${local.logs_saga} SINCE 1 hour ago LIMIT 100"
      }
    }
  }

  page {
    name = "Ordens de serviço"

    widget_billboard {
      title  = "OS abertas hoje"
      row    = 1
      column = 1
      width  = 3
      nrql_query {
        query = "SELECT count(*) ${local.logs_os} AND status_anterior IS NULL SINCE today"
      }
    }

    widget_line {
      title  = "Volume diário de OS"
      row    = 1
      column = 4
      width  = 9
      nrql_query {
        query = "SELECT count(*) AS 'OS abertas' ${local.logs_os} AND status_anterior IS NULL SINCE 7 days ago TIMESERIES 1 day"
      }
    }

    widget_bar {
      title  = "Tempo médio por status (minutos)"
      row    = 4
      column = 1
      width  = 5
      nrql_query {
        query = "SELECT average(segundos_no_status_anterior) / 60 AS 'minutos' ${local.logs_os} AND status_anterior IN ('EM_DIAGNOSTICO', 'EM_EXECUCAO', 'FINALIZADA') FACET status_anterior SINCE 7 days ago"
      }
    }

    widget_table {
      title  = "Últimas mudanças de status"
      row    = 4
      column = 6
      width  = 7
      nrql_query {
        query = "SELECT os_id, status_anterior, status_novo, segundos_no_status_anterior, correlation_id ${local.logs_os} SINCE 1 day ago LIMIT 50"
      }
    }
  }

  page {
    name = "API e integrações"

    widget_line {
      title  = "Latência da API (ms)"
      row    = 1
      column = 1
      width  = 6
      nrql_query {
        query = "SELECT percentile(duration * 1000, 95) AS 'p95', average(duration * 1000) AS 'média' ${local.app} AND transactionType = 'Web' FACET appName TIMESERIES"
      }
    }

    widget_billboard {
      title  = "Uptime em 24h (monitor externo)"
      row    = 1
      column = 7
      width  = 3
      nrql_query {
        query = "SELECT percentage(count(*), WHERE result = 'SUCCESS') AS 'uptime' FROM SyntheticCheck WHERE monitorName = '${local.monitor}' SINCE 1 day ago"
      }
    }

    widget_line {
      title  = "Healthcheck externo (ms)"
      row    = 1
      column = 10
      width  = 3
      nrql_query {
        query = "SELECT average(duration) FROM SyntheticCheck WHERE monitorName = '${local.monitor}' TIMESERIES"
      }
    }

    widget_line {
      title  = "Erros por componente"
      row    = 4
      column = 1
      width  = 6
      nrql_query {
        query = "SELECT count(*) FROM Log WHERE level = 'ERROR' FACET logger TIMESERIES"
      }
    }

    widget_line {
      title  = "Lambda de autenticação"
      row    = 4
      column = 7
      width  = 6
      nrql_query {
        query = "SELECT sum(provider.invocations.Sum) AS 'invocações', sum(provider.errors.Sum) AS 'erros' FROM ServerlessSample WHERE provider = 'LambdaFunction' TIMESERIES"
      }
    }
  }

  page {
    name = "Kubernetes"

    widget_line {
      title  = "CPU por pod (cores)"
      row    = 1
      column = 1
      width  = 6
      nrql_query {
        query = "SELECT average(cpuUsedCores) ${local.pods} FACET podName TIMESERIES"
      }
    }

    widget_line {
      title  = "Memória por pod (MiB)"
      row    = 1
      column = 7
      width  = 6
      nrql_query {
        query = "SELECT average(memoryWorkingSetBytes) / 1024 / 1024 ${local.pods} FACET podName TIMESERIES"
      }
    }

    widget_line {
      title  = "Réplicas do HPA"
      row    = 4
      column = 1
      width  = 6
      nrql_query {
        query = "SELECT latest(currentReplicas) AS 'atuais', latest(desiredReplicas) AS 'desejadas' FROM K8sHpaSample WHERE clusterName = '${var.newrelic_cluster_name}' AND namespaceName IN ${local.namespaces} FACET namespaceName TIMESERIES"
      }
    }

    widget_billboard {
      title  = "Reinícios de container na última hora"
      row    = 4
      column = 7
      width  = 6
      nrql_query {
        query = "SELECT sum(restartCountDelta) ${local.pods} SINCE 1 hour ago"
      }
    }
  }
}

resource "newrelic_synthetics_monitor" "health" {
  count            = local.newrelic_ativo ? 1 : 0
  name             = local.monitor
  type             = "SIMPLE"
  uri              = "${local.url_api}/health"
  period           = "EVERY_5_MINUTES"
  status           = "ENABLED"
  locations_public = ["US_EAST_1"]
}

resource "newrelic_alert_policy" "oficina" {
  count               = local.newrelic_ativo ? 1 : 0
  name                = "Tech Challenge · Oficina"
  incident_preference = "PER_CONDITION"
}

resource "newrelic_nrql_alert_condition" "oficina" {
  for_each = local.newrelic_ativo ? local.alertas : {}

  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = each.value.nome
  enabled                      = true
  violation_time_limit_seconds = 86400
  aggregation_window           = each.value.janela
  # Sinal contínuo (0 sem falha): o incidente fecha na recuperação ou quando o sinal some.
  aggregation_method             = "event_timer"
  aggregation_timer              = each.value.janela
  fill_option                    = "static"
  fill_value                     = 0
  expiration_duration            = each.value.janela * 3
  open_violation_on_expiration   = false
  close_violations_on_expiration = true

  nrql {
    query = each.value.consulta
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = each.value.janela
    threshold_occurrences = "at_least_once"
  }
}

resource "newrelic_notification_destination" "email" {
  count = local.email_ativo ? 1 : 0
  name  = "${var.prefixo}-email"
  type  = "EMAIL"

  property {
    key   = "email"
    value = var.email_alertas
  }
}

resource "newrelic_notification_channel" "email" {
  count          = local.email_ativo ? 1 : 0
  name           = "${var.prefixo}-email"
  type           = "EMAIL"
  product        = "IINT"
  destination_id = newrelic_notification_destination.email[0].id

  property {
    key   = "subject"
    value = "Tech Challenge: {{issueTitle}}"
  }
}

resource "newrelic_workflow" "email" {
  count                 = local.email_ativo ? 1 : 0
  name                  = "${var.prefixo}-alertas"
  muting_rules_handling = "NOTIFY_ALL_ISSUES"

  issues_filter {
    name = "politica-oficina"
    type = "FILTER"

    predicate {
      attribute = "labels.policyIds"
      operator  = "EXACTLY_MATCHES"
      values    = [newrelic_alert_policy.oficina[0].id]
    }
  }

  destination {
    channel_id = newrelic_notification_channel.email[0].id
  }
}

# 754728514883 é a conta AWS das integrações de nuvem do New Relic; o ExternalId é o ID da conta dele.
resource "aws_iam_role" "newrelic" {
  count = local.newrelic_aws ? 1 : 0
  name  = "${var.prefixo}-newrelic"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::754728514883:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.newrelic_account_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "newrelic" {
  count      = local.newrelic_aws ? 1 : 0
  role       = aws_iam_role.newrelic[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "newrelic_cloud_aws_link_account" "principal" {
  count                  = local.newrelic_aws ? 1 : 0
  name                   = var.prefixo
  arn                    = aws_iam_role.newrelic[0].arn
  metric_collection_mode = "PULL"

  depends_on = [aws_iam_role_policy_attachment.newrelic]
}

resource "newrelic_cloud_aws_integrations" "principal" {
  count             = local.newrelic_aws ? 1 : 0
  linked_account_id = newrelic_cloud_aws_link_account.principal[0].id

  lambda {
    aws_regions              = [var.regiao]
    metrics_polling_interval = 300
    fetch_tags               = true
  }
}
