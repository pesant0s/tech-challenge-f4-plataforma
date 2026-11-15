# Só existe fora do laboratório: lá o CI usa as credenciais da sessão (laboratorio.tf).

data "tls_certificate" "github" {
  count = local.laboratorio ? 0 : 1

  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.laboratorio ? 0 : 1

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "confianca_github" {
  count = local.laboratorio ? 0 : 1

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Só a main dos repositórios do dono. O GitHub envia o sub no formato clássico (repo:dono/repo)
    # ou com IDs imutáveis (repo:dono@id/repo@id); os dois são aceitos, com o ID do dono fixado.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([for repo in var.repos_github : [
        "repo:${var.org_github}/${repo}:ref:refs/heads/main",
        "repo:${var.org_github}@${var.id_dono_github}/${repo}@*:ref:refs/heads/main",
      ]])
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count = local.laboratorio ? 0 : 1

  name               = "${var.prefixo}-github-deploy"
  description        = "Assumida pelos pipelines via OIDC"
  assume_role_policy = data.aws_iam_policy_document.confianca_github[0].json
}

# Os pipelines rodam Terraform (RDS, IAM, Lambda); o limite é a confiança acima (ADR-007).
resource "aws_iam_role_policy_attachment" "github_deploy" {
  count = local.laboratorio ? 0 : 1

  role       = aws_iam_role.github_deploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Autenticar na AWS não autoriza no cluster: o EKS exige access entry.
resource "aws_eks_access_entry" "github_deploy" {
  count = local.laboratorio ? 0 : 1

  cluster_name  = aws_eks_cluster.principal.name
  principal_arn = aws_iam_role.github_deploy[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_deploy" {
  count = local.laboratorio ? 0 : 1

  cluster_name  = aws_eks_cluster.principal.name
  principal_arn = aws_iam_role.github_deploy[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_deploy]
}
