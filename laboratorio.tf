# O AWS Academy Learner Lab já traz as roles do EKS e não permite criar roles nem provedor OIDC.
# A presença delas é o sinal de que a conta é de laboratório.

data "aws_iam_roles" "lab_cluster" {
  name_regex = ".*LabEksClusterRole.*"
}

data "aws_iam_roles" "lab_node" {
  name_regex = ".*LabEksNodeRole.*"
}

# Usada pelo repositório da Lambda; consultada aqui para o contrato ficar verificável num plan.
data "aws_iam_roles" "lab_role" {
  name_regex = "^LabRole$"
}

locals {
  laboratorio = length(data.aws_iam_roles.lab_cluster.arns) > 0

  role_cluster_arn = local.laboratorio ? tolist(data.aws_iam_roles.lab_cluster.arns)[0] : aws_iam_role.cluster[0].arn
  role_node_arn    = local.laboratorio ? tolist(data.aws_iam_roles.lab_node.arns)[0] : aws_iam_role.node[0].arn
}
