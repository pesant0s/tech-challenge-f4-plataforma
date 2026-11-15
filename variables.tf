variable "regiao" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "perfil_aws" {
  description = "Perfil local do AWS CLI; vazio no CI, que autentica por OIDC ou pelas credenciais da sessão"
  type        = string
  default     = null
}

variable "prefixo" {
  description = "Prefixo dos nomes de recurso"
  type        = string
  default     = "tech-challenge-f4"
}

variable "cidr_vpc" {
  description = "CIDR da VPC; /16 porque o VPC CNI atribui um IP a cada pod"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_vpc, 0))
    error_message = "cidr_vpc precisa ser um bloco CIDR válido."
  }
}

variable "zonas_disponibilidade" {
  description = "AZs usadas; o EKS e o RDS dos serviços exigem ao menos duas"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.zonas_disponibilidade) >= 2
    error_message = "São necessárias ao menos duas zonas de disponibilidade."
  }
}

variable "versao_kubernetes" {
  description = "Versão do EKS; precisa estar em suporte padrão, pois o estendido custa 6x"
  type        = string
  default     = "1.36"
}

variable "nodes_desejados" {
  description = "Quantidade inicial de nodes"
  type        = number
  default     = 3
}

variable "nodes_minimo" {
  description = "Mínimo de nodes"
  type        = number
  default     = 2
}

variable "nodes_maximo" {
  description = "Máximo de nodes"
  type        = number
  default     = 4
}

variable "org_github" {
  description = "Dono dos repositórios no GitHub; restringe quem assume a role de deploy (fora do laboratório)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.org_github))
    error_message = "org_github deve ser um usuário ou organização do GitHub, sem barras."
  }
}

variable "id_dono_github" {
  description = "ID numérico do dono dos repositórios; o GitHub o inclui no sub do token OIDC"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.id_dono_github))
    error_message = "id_dono_github deve ser o ID numérico do usuário ou organização no GitHub."
  }
}

variable "repos_github" {
  description = "Repositórios autorizados a assumir a role via OIDC"
  type        = list(string)
  default = [
    "tech-challenge-f4-plataforma",
    "tech-challenge-f4-os-service",
    "tech-challenge-f4-execucao-service",
    "tech-challenge-f4-billing-service",
    "tech-challenge-f4-auth-lambda",
  ]
}

variable "newrelic_license_key" {
  description = "Licença do New Relic; vazia, o agente não é instalado"
  type        = string
  sensitive   = true
  default     = ""
}

variable "newrelic_api_key" {
  description = "User key do New Relic (NRAK-...); vazia, dashboards, alertas e monitor não são criados"
  type        = string
  sensitive   = true
  default     = ""
}

variable "newrelic_account_id" {
  description = "ID da conta no New Relic"
  type        = string
  default     = ""
}

variable "newrelic_regiao" {
  description = "Região da conta no New Relic: US ou EU"
  type        = string
  default     = "US"
}

variable "email_alertas" {
  description = "E-mail que recebe os alertas; vazio, os incidentes ficam só no painel do New Relic"
  type        = string
  default     = ""
}

variable "newrelic_cluster_name" {
  description = "Nome do cluster no New Relic"
  type        = string
  default     = "tech-challenge-f4-eks"
}
