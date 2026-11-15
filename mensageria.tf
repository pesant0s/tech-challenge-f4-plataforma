# RabbitMQ da Saga. emptyDir: o ambiente é efêmero e o outbox de cada serviço republica o que não foi confirmado.

locals {
  rabbitmq_usuario = "oficina"
  rabbitmq_url     = "amqp://${local.rabbitmq_usuario}:${random_password.rabbitmq.result}@rabbitmq.mensageria.svc.cluster.local:5672/%2F"
}

resource "kubernetes_namespace_v1" "mensageria" {
  metadata {
    name = "mensageria"
  }

  depends_on = [aws_eks_node_group.principal, aws_eks_addon.essenciais]
}

resource "kubernetes_secret_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace_v1.mensageria.metadata[0].name
  }

  data = {
    usuario = local.rabbitmq_usuario
    senha   = random_password.rabbitmq.result
  }
}

resource "kubernetes_deployment_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace_v1.mensageria.metadata[0].name
    labels    = { app = "rabbitmq" }
  }

  spec {
    replicas = 1

    # Com uma réplica e emptyDir, dois pods ao mesmo tempo só atrapalhariam.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "rabbitmq" }
    }

    template {
      metadata {
        labels = { app = "rabbitmq" }
      }

      spec {
        container {
          name  = "rabbitmq"
          image = "rabbitmq:4.1-management-alpine"

          port {
            name           = "amqp"
            container_port = 5672
          }

          port {
            name           = "painel"
            container_port = 15672
          }

          env {
            name  = "RABBITMQ_DEFAULT_USER"
            value = local.rabbitmq_usuario
          }

          env {
            name = "RABBITMQ_DEFAULT_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.rabbitmq.metadata[0].name
                key  = "senha"
              }
            }
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              memory = "768Mi"
            }
          }

          readiness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "-q", "check_port_connectivity"]
            }
            initial_delay_seconds = 20
            period_seconds        = 10
            timeout_seconds       = 10
          }

          liveness_probe {
            exec {
              command = ["rabbitmq-diagnostics", "-q", "check_port_connectivity"]
            }
            initial_delay_seconds = 60
            period_seconds        = 20
            timeout_seconds       = 10
            failure_threshold     = 5
          }

          volume_mount {
            name       = "dados"
            mount_path = "/var/lib/rabbitmq"
          }
        }

        volume {
          name = "dados"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace_v1.mensageria.metadata[0].name
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "rabbitmq" }

    port {
      name        = "amqp"
      port        = 5672
      target_port = "amqp"
    }

    port {
      name        = "painel"
      port        = 15672
      target_port = "painel"
    }
  }
}
