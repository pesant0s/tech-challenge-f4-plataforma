output "url_api" {
  description = "Endpoint público do API Gateway"
  value       = local.url_api
}

output "nome_cluster" {
  value = aws_eks_cluster.principal.name
}

output "comando_kubeconfig" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.principal.name} --region ${var.regiao}"
}

output "dns_nlb" {
  description = "DNS do NLB interno"
  value       = aws_lb.api.dns_name
}

output "laboratorio" {
  description = "Conta de laboratório (AWS Academy) detectada"
  value       = local.laboratorio
}

output "comando_painel_rabbitmq" {
  description = "Abre o painel do RabbitMQ em http://localhost:15672"
  value       = "kubectl -n mensageria port-forward svc/rabbitmq 15672:15672"
}

output "github_role_arn" {
  description = "Role do OIDC para os pipelines; nulo no laboratório"
  value       = one(aws_iam_role.github_deploy[*].arn)
}
