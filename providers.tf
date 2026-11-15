provider "aws" {
  region  = var.regiao
  profile = var.perfil_aws

  default_tags {
    tags = {
      Project     = "tech-challenge-f4"
      Fase        = "04"
      Repositorio = "tech-challenge-f4-plataforma"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  # Mesmo token para os providers helm e kubernetes.
  args_token_eks = concat(
    ["eks", "get-token", "--cluster-name", aws_eks_cluster.principal.name, "--region", var.regiao],
    var.perfil_aws == null ? [] : ["--profile", var.perfil_aws],
  )
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.principal.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.principal.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.args_token_eks
    }
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.principal.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.principal.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.args_token_eks
  }
}

# Sem as chaves, o provider ainda exige uma credencial para iniciar; nenhum recurso chega a usá-la.
provider "newrelic" {
  account_id = local.newrelic_ativo ? var.newrelic_account_id : "1"
  api_key    = local.newrelic_ativo ? var.newrelic_api_key : "NRAK-DESLIGADO"
  region     = var.newrelic_regiao
}
