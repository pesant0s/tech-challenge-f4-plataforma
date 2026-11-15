# Contrato de infraestrutura entre os repositórios

Este documento fixa o que cada repositório cria na AWS e no cluster, e como os outros o encontram.
Quem publica um valor no SSM é o único dono dele; quem lê não o recria.

Prefixo de nomes: `tech-challenge-f4`. Região: `us-east-1`. Tag em todo recurso AWS:
`Project = tech-challenge-f4`.

## Ordem de subida

1. `tech-challenge-f4-plataforma`: bucket de estado (`make bootstrap`), depois `make up`.
2. `tech-challenge-f4-os-service`, `tech-challenge-f4-execucao-service` e `tech-challenge-f4-billing-service`,
   em qualquer ordem e em paralelo: `make infra-up` (banco e ECR) e o pipeline de deploy.
3. `tech-challenge-f4-auth-lambda`: `make apply`, depois que o OS Service estiver no ar.

A destruição segue a ordem inversa.

## Estado do Terraform

Um bucket por conta, `tech-challenge-f4-tfstate-<conta>`, com versionamento, criptografia e bloqueio de acesso
público. Uma chave por repositório:

| Repositório | Chave |
|---|---|
| plataforma | `plataforma/terraform.tfstate` |
| os-service | `os-service/terraform.tfstate` |
| execucao-service | `execucao-service/terraform.tfstate` |
| billing-service | `billing-service/terraform.tfstate` |
| auth-lambda | `auth-lambda/terraform.tfstate` |

## Conta comum e conta de laboratório (AWS Academy)

A plataforma detecta o laboratório procurando roles cujo nome contém `LabEksClusterRole`, `LabEksNodeRole` e
`LabRole` (`data "aws_iam_roles"` com `name_regex`).

| | Conta comum | AWS Academy Learner Lab |
|---|---|---|
| Role do cluster e dos nodes | criadas pelo Terraform | `LabEksClusterRole` e `LabEksNodeRole` existentes |
| Role da Lambda | criada pelo repositório da Lambda | `LabRole` existente |
| Autenticação do CI | OIDC do GitHub (`AWS_ROLE_ARN`) | credenciais da sessão (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) |
| Capacidade dos nodes | On-Demand | On-Demand (Spot não é permitido) |
| Integração AWS do New Relic | criada se houver chaves | desligada (exige role própria) |

Os pipelines escolhem a autenticação sozinhos: com o secret `AWS_ROLE_ARN` usam OIDC; sem ele, as três
credenciais da sessão.

## Parâmetros no SSM

Todos sob `/tech-challenge-f4/`. Os `SecureString` usam a chave padrão `alias/aws/ssm`.

| Parâmetro | Tipo | Publicado por | Lido por |
|---|---|---|---|
| `rede/vpc_id` | String | plataforma | serviços (RDS), Lambda |
| `rede/cidr` | String | plataforma | serviços (RDS), Lambda |
| `rede/subnets_publicas` | String (ids separados por vírgula) | plataforma | — |
| `rede/subnets_privadas` | String (ids separados por vírgula) | plataforma | serviços (RDS), Lambda |
| `cluster/nome` | String | plataforma | pipelines dos serviços |
| `cluster/sg_id` | String | plataforma | serviços (regra de entrada do RDS) |
| `nlb/dns` | String | plataforma | Lambda |
| `apigateway/id` | String | plataforma | Lambda |
| `apigateway/endpoint` | String (sem barra no fim) | plataforma | Lambda, pipelines (teste de fumaça) |
| `apigateway/execucao_arn` | String | plataforma | Lambda |
| `segredos/jwt_secret_key` | SecureString | plataforma | os, execução, billing, Lambda |
| `segredos/token_interno` | SecureString | plataforma | os, Lambda |
| `rabbitmq/url` | SecureString | plataforma | os, execução, billing |
| `newrelic/license_key` | SecureString (`desligado` se não houver licença: o SSM não aceita valor vazio) | plataforma | os, execução, billing |
| `os-service/database_url` | SecureString | os-service | os-service |
| `execucao-service/database_url` | SecureString | execucao-service | execucao-service |

## Cluster

- EKS `tech-challenge-f4-eks`, versão 1.36, endpoint público e privado, logs do plano de controle `api` e
  `audit` com retenção de 7 dias.
- Node group `tech-challenge-f4-nodes`: 3 × `t3.medium` On-Demand (mínimo 2, máximo 4) nas subnets públicas, com
  o security group do cluster pelo launch template.
- Addons: `vpc-cni`, `coredns`, `kube-proxy`, `metrics-server`.
- Quem cria o cluster é administrador dele (`bootstrap_cluster_creator_admin_permissions`). No laboratório o CI
  usa a mesma identidade; na conta comum a role do OIDC recebe access entry de administrador.

## Namespaces e componentes no cluster

| Namespace | Dono | Conteúdo |
|---|---|---|
| `mensageria` | plataforma | RabbitMQ 4.1 com painel (1 réplica, `emptyDir`), Service `rabbitmq` nas portas 5672 e 15672 |
| `newrelic` | plataforma | `nri-bundle` (só com licença) |
| `os-service` | os-service | API do OS Service |
| `execucao-service` | execucao-service | API da Execução |
| `billing-service` | billing-service | API do Billing e MongoDB 8.0 em replica set de 1 nó (`emptyDir`, Service `mongo`) |

URL do broker dentro do cluster: `amqp://oficina:<senha>@rabbitmq.mensageria.svc.cluster.local:5672/%2F`.
O MongoDB é lido com `mongodb://mongo.billing-service.svc.cluster.local:27017/?directConnection=true`.

O RabbitMQ e o MongoDB usam `emptyDir`: o ambiente é efêmero, o EBS CSI exigiria uma role IAM própria, e o
outbox de cada serviço republica o que não tiver sido confirmado.

## Exposição

Internet → API Gateway HTTP API → VPC Link → NLB interno → NodePort → pods.

| Serviço | NodePort | Listener do NLB | Health check do target group |
|---|---|---|---|
| os-service | 30080 | 80 | `GET /health` |
| execucao-service | 30081 | 8081 | `GET /health` |
| billing-service | 30082 | 8082 | `GET /health` |

Rotas do API Gateway, criadas pela plataforma, sem reescrita de caminho:

| Rota | Destino |
|---|---|
| `ANY /auth/{proxy+}`, `ANY /cadastro/{proxy+}`, `ANY /atendimento/{proxy+}` | os-service |
| `GET /docs`, `GET /openapi.json`, `GET /redoc`, `GET /health` | os-service |
| `ANY /catalogo/{proxy+}`, `ANY /estoque/{proxy+}`, `ANY /execucao/{proxy+}` | execucao-service |
| `ANY /billing/{proxy+}` | billing-service |
| `POST /auth/cpf` | Lambda `tech-challenge-f4-auth` (rota criada pelo repositório da Lambda; a rota exata vence o `{proxy+}`) |

`/interno/*` não tem rota no gateway: só a Lambda o alcança, pelo NLB dentro da VPC
(`http://<nlb/dns>:80/interno/...`).

O Swagger da Execução e do Billing fica em `/execucao/docs` e `/billing/docs` (variável `PREFIXO_DOCS`), para
não colidir com o do OS Service em `/docs`.

## Segredo de cada serviço no cluster

O pipeline de cada serviço monta, a cada deploy, o Secret `<servico>-segredos` no namespace do serviço, lendo o
SSM:

| Chave | os-service | execucao-service | billing-service |
|---|---|---|---|
| `DATABASE_URL` | `os-service/database_url` | `execucao-service/database_url` | — |
| `MONGO_URL` | — | — | URL do MongoDB do próprio namespace |
| `SECRET_KEY` | `segredos/jwt_secret_key` | idem | idem |
| `RABBITMQ_URL` | `rabbitmq/url` | idem | idem |
| `TOKEN_INTERNO` | `segredos/token_interno` | — | — |
| `NEW_RELIC_LICENSE_KEY` | `newrelic/license_key` | idem | idem |
| `MP_ACCESS_TOKEN`, `MP_EXTERNAL_POS_ID`, `MP_WEBHOOK_SECRET` | — | — | secrets do repositório no GitHub |

## Recursos de cada serviço (`infra/` do repositório)

| | os-service | execucao-service | billing-service |
|---|---|---|---|
| ECR | `tech-challenge-f4-os-service` | `tech-challenge-f4-execucao-service` | `tech-challenge-f4-billing-service` |
| Banco | RDS PostgreSQL 16 `db.t3.micro`, 20 GB gp2, subnets privadas | idem | MongoDB no cluster (manifesto em `k8s/`) |
| Security group do banco | entrada 5432 só do `cluster/sg_id` | idem | — |
| Senha | `random_password`, publicada em `database_url` | idem | — |

O RDS não tem enhanced monitoring, Performance Insights nem snapshot final (`skip_final_snapshot = true`), para
caber nas restrições do laboratório e destruir sem sobras.

## GitHub

Variável de repositório `AMBIENTE_ATIVO` (ADR-013) nos cinco repositórios. Secrets de AWS conforme o modo de
autenticação acima. `make github-segredos`, na plataforma, grava as variáveis e os secrets nos cinco repositórios
a partir do perfil AWS local.
