# Fora do laboratório, o Terraform cria as roles; no laboratório valem as existentes (laboratorio.tf).

data "aws_iam_policy_document" "confianca_cluster" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count = local.laboratorio ? 0 : 1

  name               = "${var.prefixo}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.confianca_cluster.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = local.laboratorio ? 0 : 1

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "confianca_node" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.laboratorio ? 0 : 1

  name               = "${var.prefixo}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.confianca_node.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.laboratorio ? toset([]) : toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}
