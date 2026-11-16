# tech-challenge-f4-plataforma

Base de nuvem, contratos e documentação da solução de microsserviços da oficina mecânica: rede, cluster
Kubernetes, porta de entrada, mensageria, observabilidade e a visão geral que liga os cinco repositórios.

> Pós-Tech Software Architecture · FIAP · Tech Challenge Fase 04

[![Terraform](https://github.com/pesant0s/tech-challenge-f4-plataforma/actions/workflows/terraform.yml/badge.svg)](https://github.com/pesant0s/tech-challenge-f4-plataforma/actions/workflows/terraform.yml)
[![Contratos](https://github.com/pesant0s/tech-challenge-f4-plataforma/actions/workflows/contratos.yml/badge.svg)](https://github.com/pesant0s/tech-challenge-f4-plataforma/actions/workflows/contratos.yml)

> **Este é o repositório que gera custo por hora.** O control plane do EKS cobra US$ 0,10/h, ocupado ou
> ocioso. Com tudo ligado, o ambiente custa cerca de US$ 0,29/h (ver [Custo](#11-custo)). Use `make up`
> para trabalhar e `make down` ao terminar.

## Sumário

1. [O sistema](#1-o-sistema)
2. [Os cinco repositórios](#2-os-cinco-repositórios)
3. [Arquitetura geral](#3-arquitetura-geral)
4. [Divisão em microsserviços e escolha das tecnologias](#4-divisão-em-microsserviços-e-escolha-das-tecnologias)
5. [Estratégia da Saga](#5-estratégia-da-saga)
6. [O que a plataforma cria](#6-o-que-a-plataforma-cria)
7. [Modo laboratório (AWS Academy) e conta comum](#7-modo-laboratório-aws-academy-e-conta-comum)
8. [Contrato de infraestrutura entre os repositórios](#8-contrato-de-infraestrutura-entre-os-repositórios)
9. [Alvos do Makefile](#9-alvos-do-makefile)
10. [Subir e destruir a solução inteira](#10-subir-e-destruir-a-solução-inteira)
11. [Custo](#11-custo)
12. [Ambiente local](#12-ambiente-local)
13. [Coleção Postman](#13-coleção-postman)
14. [Contrato AsyncAPI](#14-contrato-asyncapi)
15. [Workflows da plataforma](#15-workflows-da-plataforma)
16. [Observabilidade](#16-observabilidade)
17. [Validação em nuvem](#17-validação-em-nuvem)
18. [Decisões arquiteturais](#18-decisões-arquiteturais)
19. [Limitações conhecidas](#19-limitações-conhecidas)
20. [Estrutura do repositório](#20-estrutura-do-repositório)

---

## 1. O sistema

Sistema de uma oficina mecânica. O funcionário abre uma **ordem de serviço** (OS) para um cliente e um
veículo. O sistema reserva as peças, gera o orçamento e o envia ao cliente. O cliente aprova e paga por
**QR Code dinâmico do Mercado Pago**. Com o pagamento confirmado, a OS entra na fila de execução, passa por
diagnóstico e reparo, é finalizada e entregue.

A aplicação da Fase 03 era um monólito hexagonal. Na Fase 04 ela virou **três microsserviços** e uma
**função Lambda**, cada um com repositório, pipeline, infraestrutura e banco próprios. Nenhum serviço acessa
o banco de outro. As operações que atravessam serviços (abrir a OS, cobrar, enfileirar, compensar) são uma
**Saga orquestrada** sobre o RabbitMQ.

Status de uma OS: `ABERTA`, `AGUARDANDO_APROVACAO`, `AGUARDANDO_PAGAMENTO`, `NA_FILA`, `EM_DIAGNOSTICO`,
`EM_EXECUCAO`, `FINALIZADA`, `ENTREGUE`, `NEGADA` e `CANCELADA`.

Dois tipos de usuário, com dois tipos de JWT:

| Usuário | Como obtém o token | Emissor |
|---|---|---|
| Funcionário | `POST /auth/token` (usuário e senha) | OS Service |
| Cliente | `POST /auth/cpf` (CPF ou CNPJ) | Lambda `tech-challenge-f4-auth` |

O claim `tipo` do JWT separa os dois. As três APIs validam o token com a mesma `SECRET_KEY`.

---

## 2. Os cinco repositórios

Todos na organização `pesant0s` do GitHub, com o prefixo `tech-challenge-f4-`.

| Repositório | Papel | Dados | Pacote |
|---|---|---|---|
| **[plataforma](https://github.com/pesant0s/tech-challenge-f4-plataforma)** ← você está aqui | Terraform da base de nuvem (VPC, EKS, NLB, API Gateway, SSM, RabbitMQ, New Relic), contrato de mensagens (AsyncAPI), contrato de infraestrutura, ADRs, RFC, coleção Postman e ambiente local | estado do Terraform no S3 | Terraform |
| [os-service](https://github.com/pesant0s/tech-challenge-f4-os-service) | Ordens de serviço, clientes, veículos, usuários e login de funcionário. **Orquestra a Saga** | PostgreSQL (RDS próprio) | imagem no ECR, deploy no EKS |
| [execucao-service](https://github.com/pesant0s/tech-challenge-f4-execucao-service) | Catálogo de serviços e peças, estoque (reserva, baixa e liberação), fila de execução, diagnóstico e reparo | PostgreSQL (RDS próprio) | imagem no ECR, deploy no EKS |
| [billing-service](https://github.com/pesant0s/tech-challenge-f4-billing-service) | Orçamento, aprovação pelo cliente, cobrança, cancelamento e reembolso no Mercado Pago | MongoDB (no cluster) | imagem no ECR, deploy no EKS |
| [auth-lambda](https://github.com/pesant0s/tech-challenge-f4-auth-lambda) | Autenticação do cliente por CPF: valida o documento, consulta o OS Service e emite o JWT | nenhum | zip da Lambda |

Qualidade dos quatro repositórios de código no SonarQube Cloud (selos ao vivo):

| Repositório | Quality Gate | Cobertura |
|---|---|---|
| os-service | [![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-os-service&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-os-service) | [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-os-service&metric=coverage)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-os-service) |
| execucao-service | [![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-execucao-service&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-execucao-service) | [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-execucao-service&metric=coverage)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-execucao-service) |
| billing-service | [![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-billing-service&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-billing-service) | [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-billing-service&metric=coverage)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-billing-service) |
| auth-lambda | [![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-auth-lambda&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-auth-lambda) | [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=pesant0s_tech-challenge-f4-auth-lambda&metric=coverage)](https://sonarcloud.io/summary/new_code?id=pesant0s_tech-challenge-f4-auth-lambda) |

Quem lê o quê (detalhes na [seção 8](#8-contrato-de-infraestrutura-entre-os-repositórios)):

- A **plataforma** cria a base e publica o contrato no SSM Parameter Store (`/tech-challenge-f4/*`).
- Os **serviços** leem o contrato, criam o próprio ECR e o próprio banco e implantam no cluster.
- A **Lambda** lê o contrato, cria a própria função e a própria rota no API Gateway da plataforma.

Cada repositório de serviço tem o próprio README, com arquitetura interna, modelo de dados, API, testes e
pipeline. Este README cobre o que é comum aos cinco.

---

## 3. Arquitetura geral

Os arquivos do diagrama estão em [`docs/arquitetura/`](docs/arquitetura/):
[`visao-geral.mmd`](docs/arquitetura/visao-geral.mmd) (fonte Mermaid),
[`visao-geral.svg`](docs/arquitetura/visao-geral.svg) e [`visao-geral.png`](docs/arquitetura/visao-geral.png).

```mermaid
%%{init: {"theme": "neutral", "flowchart": {"nodeSpacing": 40, "rankSpacing": 80, "curve": "basis", "htmlLabels": true}}}%%
flowchart TB
  U["Funcionário / Cliente"]
  MP["Mercado Pago<br/>Orders API · QR dinâmico"]
  NR["New Relic<br/>APM · logs · traces · dashboards"]
  GH["GitHub Actions<br/>testes · SonarQube · deploy"]
  subgraph AWS["AWS · us-east-1"]
    APIGW["API Gateway HTTP<br/>rota por prefixo"]
    L["Lambda tech-challenge-f4-auth<br/>POST /auth/cpf"]
    ECR["ECR · um por serviço"]
    SSM["SSM Parameter Store<br/>/tech-challenge-f4/*"]
    subgraph VPC["VPC"]
      NLB["NLB interno<br/>80 · 8081 · 8082"]
      subgraph EKS["EKS · 3 nós t3.medium"]
        OS["OS Service<br/>orquestrador da Saga"]
        EX["Execução e Produção"]
        BI["Billing"]
        RMQ["RabbitMQ<br/>namespace mensageria"]
        MDB[("MongoDB rs0<br/>namespace billing-service")]
      end
      RDS1[("RDS PostgreSQL<br/>os-service")]
      RDS2[("RDS PostgreSQL<br/>execucao-service")]
    end
  end
  U --> APIGW
  APIGW -->|"POST /auth/cpf"| L
  APIGW -->|"VPC Link"| NLB
  L -->|"/interno/clientes/autenticar"| NLB
  NLB -->|"NodePort 30080"| OS
  NLB -->|"NodePort 30081"| EX
  NLB -->|"NodePort 30082"| BI
  OS --- RDS1
  EX --- RDS2
  BI --- MDB
  OS <-->|"comandos e eventos"| RMQ
  EX <--> RMQ
  BI <--> RMQ
  BI -->|"cobrança · consulta · cancelamento · reembolso"| MP
  MP -.->|"webhook /billing/webhooks/mercadopago"| APIGW
  EKS -.->|"agente"| NR
  GH -->|"imagem"| ECR
  GH -->|"deploy"| EKS

  APIGW ~~~ SSM
  RDS1 ~~~ NR
  style AWS fill:#f6f8fa,stroke:#57606a
  style VPC fill:#eef3fb,stroke:#3b6ea5
  style EKS fill:#e6f2e6,stroke:#2e7d32
```

### Caminhos do diagrama

| Caminho | Como funciona |
|---|---|
| Entrada pública | Internet → API Gateway HTTP → rota por prefixo → VPC Link → NLB interno → NodePort do node → pod. Sem reescrita de caminho |
| Autenticação do cliente | `POST /auth/cpf` é uma rota exata do API Gateway que aponta para a Lambda. A Lambda, dentro da VPC, chama `POST /interno/clientes/autenticar` no NLB interno (porta 80, OS Service) com o cabeçalho `X-Token-Interno` |
| Mensageria | OS Service, Execução e Billing publicam e consomem no RabbitMQ do namespace `mensageria` (comandos e eventos da Saga) |
| Dados | OS Service e Execução: um RDS PostgreSQL por serviço, em subnets privadas. Billing: MongoDB em replica set de um nó, no namespace `billing-service` |
| Pagamento | O Billing chama o Mercado Pago (Orders API). O Mercado Pago chama de volta o webhook `/billing/webhooks/mercadopago` pelo API Gateway |
| Observabilidade | O agente do New Relic (`nri-bundle`, no namespace `newrelic`) coleta o cluster e os logs dos pods; o agente Python nos serviços envia APM e traces |
| Entrega | GitHub Actions publica a imagem no ECR e implanta no EKS |
| Contrato entre repositórios | SSM Parameter Store, prefixo `/tech-challenge-f4/` |

### Rotas do API Gateway

A API HTTP `tech-challenge-f4-api` usa o estágio `$default`, com `auto_deploy`. Todas as rotas passam o
caminho original para o serviço (sem reescrita).

| Rota | Destino | Porta do NLB / NodePort |
|---|---|---|
| `ANY /auth/{proxy+}`, `ANY /cadastro/{proxy+}`, `ANY /atendimento/{proxy+}` | os-service | 80 / 30080 |
| `GET /docs`, `GET /openapi.json`, `GET /redoc`, `GET /health` | os-service | 80 / 30080 |
| `ANY /catalogo/{proxy+}`, `ANY /estoque/{proxy+}`, `ANY /execucao/{proxy+}` | execucao-service | 8081 / 30081 |
| `ANY /billing/{proxy+}` | billing-service | 8082 / 30082 |
| `POST /auth/cpf` | Lambda `tech-challenge-f4-auth` (rota criada pelo repositório da Lambda; a rota exata vence o `{proxy+}`) | — |

`/interno/*` **não tem rota no gateway**: só a Lambda o alcança, pelo NLB, dentro da VPC.

O Swagger do OS Service fica em `<url_api>/docs`. Execução e Billing usam a variável `PREFIXO_DOCS` e expõem
`<url_api>/execucao/docs` e `<url_api>/billing/docs`, para não colidir com o do OS Service.

### Segurança e rede

- **Sem NAT Gateway.** As subnets privadas não têm rota para a internet; os nodes ficam nas subnets públicas
  (o endpoint do EKS é público e privado, e o CI e o `kubectl` dependem do público).
- **O gateway não valida o JWT.** Não há authorizer nas rotas. Cada serviço valida o token com a
  `SECRET_KEY` compartilhada e confere o perfil.
- **Banco fechado.** Cada RDS aceita a porta 5432 só do security group do cluster (`cluster/sg_id`).
- **NodePorts** 30080 a 30082 liberados no security group do cluster apenas para o CIDR da VPC.
- **VPC Link** com security group próprio, com saída só para os listeners 80, 8081 e 8082 do CIDR da VPC.
- **Limite de requisições** no estágio do gateway: 50 por segundo, com rajada de 100.
- **Cabeçalhos injetados pelo gateway:** `x-request-id` (igual ao `requestId` do gateway, vira o
  `correlation_id` da API) e `x-cliente-ip` (IP de origem, usado no limite de tentativas de login).

---

## 4. Divisão em microsserviços e escolha das tecnologias

Fonte: [ADR-017](docs/adr/ADR-017-divisao-em-microsservicos.md) a
[ADR-024](docs/adr/ADR-024-ambientes.md) e [RFC-001](docs/rfc/RFC-001-nuvem.md).

### Por que três serviços

O desafio exige ao menos três microsserviços independentes, cada um com repositório, infraestrutura e banco
próprios, e proíbe um serviço de acessar o banco de outro. A divisão segue as três áreas da oficina.

| Serviço | Responsabilidade | Módulos da Fase 03 que absorve |
|---|---|---|
| **OS Service** | Abertura, status e histórico da OS; clientes, veículos, usuários e login; orquestra a Saga | atendimento, cadastro, autenticação |
| **Execução e Produção** | Catálogo de serviços e peças, estoque (reserva, baixa e liberação), fila de execução, diagnóstico e reparo | catálogo, estoque, fila de OS |
| **Billing** | Orçamento, aprovação pelo cliente, cobrança e reembolso no Mercado Pago | aprovação e rejeição da OS, webhook de resposta do cliente |

Motivos:

- Cada serviço é dono de um conjunto de dados que só ele altera: a OS e quem a pediu; o que há em estoque e
  na fila; o que foi cobrado.
- Cadastro e autenticação ficam com a OS porque toda OS nasce de um cliente e de um veículo. Um quarto
  serviço criaria uma chamada síncrona em toda abertura de OS, sem ganho.
- Catálogo e estoque ficam com a Execução porque a reserva de peças precisa do preço e da quantidade na mesma
  transação.
- O preço dos itens passa a vir da Execução, na resposta da reserva (`PecasReservadas`). O OS Service não
  conhece catálogo nem estoque.
- A aprovação do orçamento sai do OS Service e vai para o Billing; o OS Service só recebe o resultado.

### Por que cada tecnologia

| Tecnologia | Uso | Por que | Alternativas descartadas |
|---|---|---|---|
| **PostgreSQL** (RDS) | OS Service e Execução | OS: cliente, veículo, OS, histórico e estado da Saga são relacionais, e a transição de status precisa de trava de linha. Execução: a reserva de estoque usa `SELECT ... FOR UPDATE` e a fila usa `FOR UPDATE SKIP LOCKED`, que o PostgreSQL oferece pronto. É o banco da Fase 03, com as migrations prontas ([ADR-020](docs/adr/ADR-020-banco-por-servico.md)) | — |
| **MongoDB** (no cluster) | Billing | Orçamento e pagamento são documentos fechados por OS, com itens e tentativas de cobrança embutidos. A atualização condicional (`updateOne` com filtro de estado) dá a idempotência das notificações do Mercado Pago sem tabela auxiliar. É o banco não relacional da solução ([ADR-020](docs/adr/ADR-020-banco-por-servico.md)) | DocumentDB: sem free tier e cobrado por hora; o MongoDB no cluster usa a mesma imagem do docker compose |
| **RabbitMQ** (no cluster) | Mensageria da Saga | Roda igual no docker compose e no EKS, sem emulador. Exchange `topic` com chave `<serviço>.<mensagem>`: cada serviço declara só as filas que consome. Quorum queue com `x-delivery-limit` leva a mensagem envenenada à DLQ sem laço infinito. O painel de gestão mostra filas, taxas e DLQ ([ADR-019](docs/adr/ADR-019-rabbitmq.md)) | Amazon SQS + SNS (exigiria emulador local e prenderia o código ao provedor); Amazon MQ (cobra por hora, mesmo parado); Kafka ou MSK (log distribuído é mais do que a Saga precisa; operação e custo maiores) |
| **REST síncrono** | Rotas públicas e consulta da Lambda ao OS Service | Perguntas com resposta imediata continuam em REST ([ADR-019](docs/adr/ADR-019-rabbitmq.md), [ADR-022](docs/adr/ADR-022-lambda-consulta-o-os-service.md)) | — |
| **Amazon EKS** | Cluster Kubernetes | O desafio exige deploy em Kubernetes. Na AWS os serviços se encaixam sem peças intermediárias: a Lambda roda na mesma VPC, o API Gateway alcança o cluster por VPC Link e uma única role OIDC atende os pipelines ([RFC-001](docs/rfc/RFC-001-nuvem.md)) | AKS e GKE: planos de controle mais baratos, mas sem a experiência prévia do time (custo contido por ambiente efêmero, sem NAT e AWS Budget) |
| **API Gateway HTTP + VPC Link + NLB interno** | Porta de entrada | O NLB é do Terraform, não do Kubernetes: o gateway precisa do ARN do listener, e um `Service` do tipo `LoadBalancer` só criaria esse listener depois do deploy, que depende do gateway (dependência circular). Os serviços viram `NodePort` em portas fixas e o `kube-proxy` encaminha ao pod ([ADR-005](#decisões-herdadas-da-fase-03)) | `Service` `LoadBalancer` com AWS Load Balancer Controller (duas etapas de apply) |
| **Lambda** | Autenticação por CPF | O desafio pede uma função serverless que valide o CPF e devolva um JWT. Na Fase 04 ela não lê mais o banco: consulta o OS Service ([ADR-022](docs/adr/ADR-022-lambda-consulta-o-os-service.md)) | Login dentro da API (não é serverless); authorizer no gateway (não devolve JWT) |
| **Mercado Pago** (Orders API, QR dinâmico) | Pagamento | Exigência do desafio. Atrás de uma porta (`ProvedorPagamento`) com adapter `mercadopago` e adapter `simulado`, escolhido por `PAGAMENTO_PROVEDOR` ([ADR-023](docs/adr/ADR-023-mercado-pago.md)) | — |
| **Terraform** | Infraestrutura da plataforma, dos bancos e da Lambda | Todo recurso AWS é código. O estado fica no S3, com bloqueio nativo por arquivo (`use_lockfile`) | — |
| **SSM Parameter Store** | Contrato entre repositórios e segredos compartilhados | Quem publica um parâmetro é o único dono dele; quem lê não o recria. Valores sensíveis usam `SecureString` com a chave padrão `alias/aws/ssm` | — |
| **GitHub Actions** | CI/CD dos cinco repositórios | Testes, qualidade, build da imagem, deploy no EKS e teste de fumaça; autenticação OIDC ou credenciais temporárias do laboratório | — |
| **New Relic** | Observabilidade | APM, logs, traces distribuídos (inclusive através do RabbitMQ), dashboard, alertas e monitor de uptime num só lugar, tudo definido em Terraform ([seção 16](#16-observabilidade)) | — |
| **SonarQube Cloud** | Qualidade e cobertura | O desafio exige análise estática no CI. O job `Qualidade (SonarQube Cloud)` roda em todo Pull Request, com `sonar.qualitygate.wait=true`, e é check obrigatório da `main` dos quatro repositórios de código | — |

O que pesa contra o EKS ([RFC-001](docs/rfc/RFC-001-nuvem.md)): o plano de controle é cobrado por hora e não
tem free tier. A proposta aceita o custo e o contém com ambiente efêmero (ligado só em sessões de trabalho),
sem NAT Gateway, versão do Kubernetes fixada em suporte padrão (o suporte estendido custa seis vezes mais) e
AWS Budget com alertas. Todo recurso leva a tag `Project = tech-challenge-f4`.

---

## 5. Estratégia da Saga

Fonte: [ADR-018](docs/adr/ADR-018-saga-orquestrada.md), [ADR-021](docs/adr/ADR-021-outbox-e-idempotencia.md),
[`docs/contratos/asyncapi.yaml`](docs/contratos/asyncapi.yaml) e o código do orquestrador
(`app/domain/saga.py` no [os-service](https://github.com/pesant0s/tech-challenge-f4-os-service)). O detalhe da
implementação (tabelas, casos de uso, mensageria, testes BDD) está no README do OS Service.

### Por que orquestrada

Abrir uma OS passa por três serviços: reservar peças (Execução), orçar e cobrar (Billing), enfileirar para
execução (Execução). Cada passo grava no banco do próprio serviço, então não existe transação única. Se um
passo falha, os anteriores precisam ser desfeitos.

| Critério | Orquestrada (escolhida) | Coreografada |
|---|---|---|
| Onde está a regra do fluxo | Numa classe (`SagaAberturaOS`), num serviço | Espalhada pelos três serviços |
| Compensação | Explícita, na ordem inversa, disparada pelo orquestrador | Cada serviço escuta as falhas dos outros e decide sozinho |
| Estado da Saga | Uma linha consultável em `saga_instancia` | Reconstruído a partir dos eventos |
| Prazo de um passo | Varredura de `saga_instancia.expira_em` | Cada participante precisa de um temporizador próprio |
| Teste do fluxo completo | BDD num repositório, com participantes simulados | Exige subir os três serviços |
| Acoplamento | O orquestrador conhece todos os passos | Nenhum serviço conhece o fluxo inteiro |

Motivos:

- O fluxo é linear e tem um dono natural: a OS. Quem precisa saber em que passo ela está é o OS Service.
- A compensação mais delicada, reembolsar quando a execução não pode começar, depende de saber que o
  pagamento foi confirmado. Na orquestração essa informação está numa linha; na coreografia, o Billing teria
  de escutar eventos da Execução e decidir sozinho.
- Com três serviços, o custo da orquestração (um ponto que conhece o fluxo) é pequeno, e o ganho em clareza,
  teste e demonstração é grande.

Consequências aceitas:

- O OS Service concentra o conhecimento do fluxo. Um passo novo muda o orquestrador e o participante.
- Execução e Billing não se conhecem; só respondem a comandos.
- Toda compensação é idempotente, porque o orquestrador pode repeti-la depois de uma falha.
- A Saga pode parar em `FALHA_NA_COMPENSACAO` (reembolso recusado pelo provedor). Esse estado gera alerta e
  exige ação humana.

### Fluxo

Arquivos: [`saga.mmd`](docs/arquitetura/saga.mmd), [`saga.svg`](docs/arquitetura/saga.svg) e
[`saga.png`](docs/arquitetura/saga.png). O OS Service envia **comandos** pela exchange `oficina.comandos` e
reage aos **eventos** que Execução e Billing publicam em `oficina.eventos`.

```mermaid
sequenceDiagram
  autonumber
  participant F as Funcionário / Cliente
  participant OS as OS Service<br/>orquestrador
  participant EX as Execução e Produção
  participant BI as Billing
  participant MP as Mercado Pago

  rect rgb(232, 245, 233)
    Note over F,MP: Caminho feliz
    F->>OS: abre a OS
    Note over OS: OS ABERTA · Saga em RESERVANDO_PECAS
    OS->>EX: ReservarPecas
    EX-->>OS: PecasReservadas (itens com preço)
    OS->>BI: GerarOrcamento
    BI-->>OS: OrcamentoGerado
    Note over OS: OS AGUARDANDO_APROVACAO
    F->>BI: aprova o orçamento
    BI-->>OS: OrcamentoAprovado
    Note over OS: OS AGUARDANDO_PAGAMENTO
    OS->>BI: Cobrar
    BI->>MP: POST /v1/orders (QR dinâmico)
    BI-->>OS: CobrancaCriada
    F->>MP: paga o QR no aplicativo
    MP-->>BI: pedido processed (conciliação periódica ou webhook)
    BI-->>OS: PagamentoConfirmado
    OS->>EX: EnfileirarOS
    EX-->>OS: OSEnfileirada
    Note over OS: OS NA_FILA · depois daqui a oficina não cancela mais
    F->>EX: chama a próxima OS da fila
    EX-->>OS: DiagnosticoIniciado
    F->>EX: inicia o reparo
    EX-->>OS: ExecucaoIniciada
    F->>EX: finaliza a execução
    EX-->>OS: ExecucaoFinalizada
    Note over OS: OS FINALIZADA · Saga CONCLUIDA
    F->>OS: entrega o veículo
    Note over OS: OS ENTREGUE
  end

  rect rgb(255, 243, 224)
    Note over F,MP: Compensações · uma por vez, na ordem inversa dos passos concluídos
    alt ReservaRecusada
      EX-->>OS: ReservaRecusada
      Note over OS: nada a desfazer · OS CANCELADA
    else OrcamentoRejeitado (cliente rejeita ou orçamento expira)
      BI-->>OS: OrcamentoRejeitado (ORCAMENTO_REJEITADO ou ORCAMENTO_EXPIRADO)
      OS->>EX: LiberarReserva
      EX-->>OS: ReservaLiberada
      Note over OS: OS NEGADA se o motivo é ORCAMENTO_REJEITADO · senão CANCELADA
    else PagamentoRecusado (QR expirado ou recusado)
      BI-->>OS: PagamentoRecusado
      OS->>BI: CancelarOrcamento
      BI-->>OS: OrcamentoCancelado
      OS->>EX: LiberarReserva
      EX-->>OS: ReservaLiberada
      Note over OS: OS CANCELADA
    else EnfileiramentoRecusado, ou prazo esgotado depois do pagamento
      EX-->>OS: EnfileiramentoRecusado
      OS->>BI: Reembolsar
      BI->>MP: POST /v1/orders/{id}/refund
      BI-->>OS: PagamentoReembolsado
      OS->>BI: CancelarOrcamento
      BI-->>OS: OrcamentoCancelado
      OS->>EX: LiberarReserva
      EX-->>OS: ReservaLiberada
      Note over OS: OS CANCELADA
    else pagamento tardio (a oficina cancela e o pagamento chega depois)
      F->>OS: cancela a OS (possível até o passo AGUARDANDO_PAGAMENTO)
      Note over OS: Saga COMPENSANDO · CancelarOrcamento e LiberarReserva pendentes
      BI-->>OS: PagamentoConfirmado
      Note over OS: acrescenta Reembolsar ao fim das compensações pendentes
      OS->>BI: Reembolsar
      BI->>MP: POST /v1/orders/{id}/refund
      BI-->>OS: PagamentoReembolsado
      Note over OS: OS CANCELADA · Saga COMPENSADA
    else ReembolsoFalhou
      BI-->>OS: ReembolsoFalhou
      Note over OS: Saga em FALHA_NA_COMPENSACAO · alerta e ação humana
    end
  end
```

Passos e mensagens:

| Passo da Saga | Comando enviado | Sucesso | Falha | Status da OS ao concluir o passo |
|---|---|---|---|---|
| `RESERVANDO_PECAS` | `ReservarPecas` | `PecasReservadas` | `ReservaRecusada` | inalterado (`ABERTA`) |
| `GERANDO_ORCAMENTO` | `GerarOrcamento` | `OrcamentoGerado` | — | `AGUARDANDO_APROVACAO` |
| `AGUARDANDO_APROVACAO` | — | `OrcamentoAprovado` | `OrcamentoRejeitado` | `AGUARDANDO_PAGAMENTO` |
| `AGUARDANDO_PAGAMENTO` | `Cobrar` | `PagamentoConfirmado` | `PagamentoRecusado` | inalterado (`AGUARDANDO_PAGAMENTO`) |
| `ENFILEIRANDO` | `EnfileirarOS` | `OSEnfileirada` | `EnfileiramentoRecusado` | `NA_FILA` |
| `EM_EXECUCAO` | — | `ExecucaoFinalizada` | — | `EM_DIAGNOSTICO` → `EM_EXECUCAO` → `FINALIZADA` |

A entrega ao cliente (`FINALIZADA` → `ENTREGUE`) é uma ação do funcionário no OS Service, fora da Saga.
Estados da Saga: `EM_ANDAMENTO`, `COMPENSANDO`, `CONCLUIDA`, `COMPENSADA` e `FALHA_NA_COMPENSACAO`.

### Compensações

O orquestrador desfaz os passos concluídos do mais recente para o mais antigo, **uma compensação por vez**:
só envia a próxima depois de receber a confirmação da anterior.

| Compensação | Comando | Confirmação | Enviada quando |
|---|---|---|---|
| 1ª | `Reembolsar` | `PagamentoReembolsado` | houve pagamento confirmado |
| 2ª | `CancelarOrcamento` | `OrcamentoCancelado` | há orçamento ativo |
| 3ª | `LiberarReserva` | `ReservaLiberada` | há reserva de peças |

| Falha | Compensações, em ordem | Status final da OS |
|---|---|---|
| `ReservaRecusada` | nenhuma: nada foi reservado | `CANCELADA` |
| `OrcamentoRejeitado` com motivo `ORCAMENTO_REJEITADO` | `LiberarReserva` | `NEGADA` |
| `OrcamentoRejeitado` com motivo `ORCAMENTO_EXPIRADO` | `LiberarReserva` | `CANCELADA` |
| `PagamentoRecusado` (recusa ou QR expirado) | `CancelarOrcamento` → `LiberarReserva` | `CANCELADA` |
| `EnfileiramentoRecusado` | `Reembolsar` → `CancelarOrcamento` → `LiberarReserva` | `CANCELADA` |
| Prazo do passo esgotado | as do ponto em que parou, com motivo `PRAZO_ESGOTADO` | `CANCELADA` |
| Cancelamento pela oficina (`POST /atendimento/os/{id}/cancelar`) | as do ponto em que está, com motivo `CANCELADA_PELA_OFICINA` | `CANCELADA` |
| `ReembolsoFalhou` | a Saga para em `FALHA_NA_COMPENSACAO` e gera alerta | inalterado |

Regras que completam a tabela:

- **Status final.** A OS termina `NEGADA` quando o motivo é `ORCAMENTO_REJEITADO`; em qualquer outro motivo,
  `CANCELADA`.
- **Pagamento tardio.** O pagamento que chega depois da decisão de compensar (com a Saga em `COMPENSANDO` ou já
  `COMPENSADA`) ganha a compensação `Reembolsar`, acrescentada ao fim das pendentes. Se a Saga já estava
  `COMPENSADA`, ela volta para `COMPENSANDO`.
- **Sem resposta, desfaz por garantia.** Se o prazo esgota sem a resposta de um comando, o orquestrador supõe
  que o efeito pode ter acontecido (reserva feita, orçamento criado) e compensa. Como as compensações são
  idempotentes, desfazer o que não existe responde com a confirmação, sem erro.
- **Cancelamento da oficina.** Só vale nos passos `RESERVANDO_PECAS`, `GERANDO_ORCAMENTO`,
  `AGUARDANDO_APROVACAO` e `AGUARDANDO_PAGAMENTO`. Depois que a OS entra na fila de execução, a oficina não
  pode mais cancelar.
- **Eventos fora de hora.** O orquestrador confere se o evento corresponde ao passo atual e descarta, com log,
  eventos de passos já superados.

### Prazos

Cada passo tem um prazo (`saga_instancia.expira_em`), verificado por uma varredura periódica.

| Prazo | Valor | Variável | Ao expirar |
|---|---|---|---|
| Resposta de um comando | 300 s | `SAGA_PRAZO_RESPOSTA_SEGUNDOS` | Antes do pagamento, compensa com `PRAZO_ESGOTADO`. Em `ENFILEIRANDO`, reenvia `EnfileirarOS` até 3 vezes e depois compensa. Em `COMPENSANDO`, reenvia o comando de compensação pendente |
| Aprovação do orçamento | 24 h, ou o vencimento do orçamento mais 5 min de folga, o que vier antes | `SAGA_PRAZO_APROVACAO_HORAS` | Compensa |
| Pagamento | vencimento do QR (15 min por padrão no Billing) mais 5 min de folga | `PAGAMENTO_EXPIRACAO_MINUTOS` (Billing) | Compensa |
| Varredura | 30 s | `SAGA_VARREDURA_SEGUNDOS` | — |
| `EM_EXECUCAO` | sem prazo | — | — |

### Garantias de entrega

| Garantia | Como |
|---|---|
| **Outbox transacional** | A mensagem é gravada na tabela (PostgreSQL) ou coleção (MongoDB) `outbox` na mesma transação da mudança de estado. Um relay, no mesmo processo, lê o que não foi publicado, publica com *publisher confirms* e só então marca como publicado. Se o serviço cair entre o commit e a publicação, a mensagem sai depois |
| **Idempotência do consumidor (inbox)** | O consumidor grava o `message_id` em `mensagens_processadas` na mesma transação do efeito. Se o `message_id` já existe, confirma sem repetir o efeito. A entrega é "pelo menos uma vez", e a inbox torna o efeito "exatamente uma vez" |
| **`ack` manual** | Enviado só depois do commit. Erro inesperado → `nack` com reentrega |
| **DLQ** | Quorum queue com `x-delivery-limit: 5`: depois de seis entregas sem `ack` (a primeira e cinco reentregas), a mensagem vai para `<fila>.dlq`, na exchange `oficina.dlx`. Ninguém consome a DLQ: ela serve à inspeção das mensagens |
| **Compensações idempotentes** | Liberar uma reserva inexistente ou cancelar um orçamento já cancelado responde com o evento de confirmação |
| **Prazo (timeout)** | Varredura de `saga_instancia.expira_em`, tabela acima |
| **Ordem** | Não é garantida entre filas; o orquestrador descarta eventos de passos superados |
| **Rastreamento** | Os cabeçalhos AMQP `traceparent`, `tracestate` e `newrelic` carregam o contexto do trace de um serviço ao outro |

O relay pode publicar uma mensagem duas vezes (cai depois de publicar e antes de marcar); a inbox do
consumidor absorve a repetição. O outbox também resolve o broker efêmero: se o RabbitMQ for recriado, o que
não foi confirmado é publicado de novo.

---

## 6. O que a plataforma cria

Terraform na raiz do repositório. Estado remoto no bucket `tech-challenge-f4-tfstate-<conta>`, chave
`plataforma/terraform.tfstate`. Região `us-east-1`. Todo recurso AWS leva as tags `Project`, `Fase`,
`Repositorio` e `ManagedBy` (`default_tags` do provider).

| Arquivo | Recursos |
|---|---|
| `rede.tf` | VPC `10.0.0.0/16` (`tech-challenge-f4-vpc`), internet gateway, 2 subnets públicas e 2 subnets privadas (uma por zona, `us-east-1a` e `us-east-1b`), tabelas de rota. A tabela das privadas não tem rota default: **sem NAT Gateway** |
| `eks.tf` | Cluster `tech-challenge-f4-eks` (Kubernetes 1.36, endpoint público e privado, logs `api` e `audit` por 7 dias, `authentication_mode = API_AND_CONFIG_MAP`); launch template dos nodes (IMDSv2 obrigatório, security group do cluster); node group `tech-challenge-f4-nodes`; addons `vpc-cni`, `kube-proxy`, `coredns` e `metrics-server` |
| `iam_eks.tf` | Roles do cluster e dos nodes, **só fora do laboratório** |
| `laboratorio.tf` | Detecção do AWS Academy pelas roles `Lab*` ([seção 7](#7-modo-laboratório-aws-academy-e-conta-comum)) |
| `exposicao.tf` | NLB interno `tech-challenge-f4-nlb`; 3 target groups TCP (30080, 30081, 30082) com health check HTTP em `/health`; 3 listeners (80, 8081, 8082); anexo do auto scaling group do node group aos target groups; regra do security group do cluster para os NodePorts; VPC Link e seu security group; API HTTP `tech-challenge-f4-api` (CORS aberto, estágio `$default` com access log JSON no CloudWatch, 7 dias); 3 integrações `HTTP_PROXY` por VPC Link; 11 rotas |
| `mensageria.tf` | Namespace `mensageria`, Secret `rabbitmq`, Deployment e Service do RabbitMQ |
| `segredos.tf` | Três senhas aleatórias: `jwt` (64 caracteres), `token_interno` (48) e `rabbitmq` (32) |
| `ssm_contrato.tf` | Parâmetros do contrato no SSM ([seção 8](#8-contrato-de-infraestrutura-entre-os-repositórios)) |
| `oidc_github.tf` | Provedor OIDC do GitHub, role de deploy e access entry do EKS, **só fora do laboratório** |
| `newrelic.tf` | `nri-bundle` (Helm, chart 8.0.24) no namespace `newrelic`, **só com a licença** |
| `observabilidade.tf` | Dashboard, política e condições de alerta, monitor de uptime, canal de e-mail e, fora do laboratório, a integração AWS do New Relic ([seção 16](#16-observabilidade)) |
| `outputs.tf`, `variables.tf`, `providers.tf`, `versions.tf` | Saídas, variáveis, providers e versões |

### Cluster e nodes

| Item | Valor |
|---|---|
| Nome do cluster | `tech-challenge-f4-eks` |
| Versão do Kubernetes | 1.36 (variável `versao_kubernetes`; precisa estar em suporte padrão) |
| Node group | `tech-challenge-f4-nodes`, `ON_DEMAND`, `t3.medium`, nas subnets públicas |
| Capacidade | desejado 3, mínimo 2, máximo 4 (o `desired_size` é ignorado depois da criação) |
| Atualização dos nodes | `max_unavailable = 1` |
| Autoscaler de nodes | não há; o máximo de 4 vale para escala manual |
| Escala dos pods | HPA em cada serviço (2 a 4 réplicas, 70% de CPU), possível porque o `metrics-server` é addon |

### RabbitMQ no cluster

| Item | Valor |
|---|---|
| Imagem | `rabbitmq:4.1-management-alpine` |
| Réplicas | 1, estratégia `Recreate` |
| Armazenamento | `emptyDir` (os dados somem se o pod for recriado) |
| Recursos | requests 200m de CPU e 512Mi; limite de memória 768Mi |
| Probes | `rabbitmq-diagnostics -q check_port_connectivity` (readiness após 20 s, liveness após 60 s) |
| Service | `rabbitmq` (ClusterIP), portas 5672 (`amqp`) e 15672 (`painel`) |
| Usuário | `oficina`; a senha está no Secret `rabbitmq` (chave `senha`) e no parâmetro SSM `rabbitmq/url` |
| URL dentro do cluster | `amqp://oficina:<senha>@rabbitmq.mensageria.svc.cluster.local:5672/%2F` |

Painel de gestão: `make rabbitmq` e abrir http://localhost:15672. Para ler a senha:

```bash
kubectl -n mensageria get secret rabbitmq -o jsonpath='{.data.senha}' | base64 -d
```

### Variáveis do Terraform

O `make` preenche `org_github` e `id_dono_github` sozinho (remote `origin` e `gh api`). As chaves do New Relic
vêm das variáveis de ambiente `NEW_RELIC_LICENSE_KEY`, `NEW_RELIC_API_KEY`, `NEW_RELIC_ACCOUNT_ID` e
`EMAIL_ALERTAS`; um `terraform.tfvars` (não versionado, modelo em `terraform.tfvars.example`) prevalece.

| Variável | Padrão | Descrição |
|---|---|---|
| `regiao` | `us-east-1` | Região AWS |
| `perfil_aws` | `null` | Perfil local do AWS CLI; vazio no CI |
| `prefixo` | `tech-challenge-f4` | Prefixo dos nomes de recurso |
| `cidr_vpc` | `10.0.0.0/16` | CIDR da VPC (/16 porque o VPC CNI atribui um IP a cada pod) |
| `zonas_disponibilidade` | `["us-east-1a", "us-east-1b"]` | Ao menos duas: o EKS e o RDS dos serviços exigem |
| `versao_kubernetes` | `1.36` | Versão do EKS |
| `nodes_desejados` · `nodes_minimo` · `nodes_maximo` | `3` · `2` · `4` | Capacidade do node group |
| `org_github` | obrigatória | Dono dos repositórios; restringe quem assume a role de deploy |
| `id_dono_github` | obrigatória | ID numérico do dono; o GitHub o inclui no `sub` do token OIDC |
| `repos_github` | os 5 repositórios | Repositórios autorizados a assumir a role via OIDC |
| `newrelic_license_key` | `""` | Licença; vazia, o agente não é instalado |
| `newrelic_api_key` | `""` | User key (`NRAK-...`); vazia, dashboard, alertas e monitor não são criados |
| `newrelic_account_id` | `""` | ID da conta no New Relic |
| `newrelic_regiao` | `US` | Região da conta: `US` ou `EU` |
| `email_alertas` | `""` | Destino dos alertas; vazio, os incidentes ficam só no painel |
| `newrelic_cluster_name` | `tech-challenge-f4-eks` | Nome do cluster no New Relic |

### Saídas (`make output`)

| Saída | Conteúdo |
|---|---|
| `url_api` | Endpoint público do API Gateway (sem barra no fim) |
| `nome_cluster` | `tech-challenge-f4-eks` |
| `comando_kubeconfig` | Comando que aponta o `kubectl` para o cluster |
| `dns_nlb` | DNS do NLB interno |
| `laboratorio` | `true` se a conta foi detectada como laboratório |
| `comando_painel_rabbitmq` | Comando do painel do RabbitMQ |
| `github_role_arn` | Role do OIDC; nula no laboratório |

### Providers

`required_version >= 1.10` (o bloqueio de estado por arquivo, `use_lockfile`, exige Terraform 1.10 ou mais
novo). Providers: `aws ~> 5.60`, `helm ~> 2.14`, `kubernetes ~> 2.31`, `newrelic ~> 3.97`, `random ~> 3.6` e
`tls ~> 4.0`. O `.terraform.lock.hcl` fixa as versões resolvidas.

---

## 7. Modo laboratório (AWS Academy) e conta comum

A plataforma roda em dois tipos de conta e detecta sozinha em qual está. O AWS Academy Learner Lab já traz
as roles do EKS e não permite criar roles nem provedor OIDC.

**Detecção** (`laboratorio.tf`): `data "aws_iam_roles"` procura roles com nome que contenha
`LabEksClusterRole` e `LabEksNodeRole`, e a role `LabRole` (usada pela Lambda). Se existir alguma
`LabEksClusterRole`, `local.laboratorio` é verdadeiro. A saída `laboratorio` mostra o resultado.

| | Conta comum | AWS Academy Learner Lab |
|---|---|---|
| Role do cluster e dos nodes | criadas pelo Terraform (`tech-challenge-f4-eks-cluster` e `tech-challenge-f4-eks-node`) | `LabEksClusterRole` e `LabEksNodeRole` existentes |
| Role da Lambda | criada pelo repositório da Lambda | `LabRole` existente |
| Provedor OIDC, role de deploy e access entry do EKS | criados | não criados |
| Autenticação do CI | OIDC do GitHub (secret `AWS_ROLE_ARN`) | credenciais temporárias do laboratório (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) |
| Capacidade dos nodes | On-Demand | On-Demand (Spot não é permitido) |
| Integração AWS do New Relic (métricas da Lambda) | criada se houver chaves do New Relic | desligada (exige role própria) |
| Saída `github_role_arn` | ARN da role | nula |

Como o CI escolhe a autenticação: com o secret `AWS_ROLE_ARN` usa OIDC; sem ele, usa as três credenciais
temporárias. `make github-segredos` grava o que couber em cada modo:

- **Laboratório** (detectado por `LabEksClusterRole`): grava `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e
  `AWS_SESSION_TOKEN` nos cinco repositórios e apaga `AWS_ROLE_ARN`, que levaria os pipelines ao OIDC, que não
  existe lá. **As credenciais do laboratório expiram: rode o alvo de novo a cada vez que o laboratório for
  iniciado.**
- **Conta comum**: grava `AWS_ROLE_ARN` (lido de `terraform output github_role_arn`, por isso exige o `make up`
  antes).

No modo conta comum, a role de deploy (`tech-challenge-f4-github-deploy`) tem `AdministratorAccess`, porque os
pipelines rodam Terraform (RDS, IAM, Lambda), e recebe a access entry `AmazonEKSClusterAdminPolicy`. O limite é
a condição de confiança: só a `main` dos cinco repositórios do dono assume a role, e só por OIDC. A condição
aceita os dois formatos do `sub` que o GitHub envia (o clássico, `repo:<dono>/<repo>:ref:refs/heads/main`, e o de
IDs imutáveis, `repo:<dono>@<id>/<repo>@<id>:ref:refs/heads/main`), com o ID do dono fixado.

---

## 8. Contrato de infraestrutura entre os repositórios

Fonte completa: [`docs/infraestrutura/contrato.md`](docs/infraestrutura/contrato.md). Resumo:

**Regra.** Quem publica um valor no SSM é o único dono dele; quem lê não o recria. Prefixo de nomes
`tech-challenge-f4`, região `us-east-1`, tag `Project = tech-challenge-f4` em todo recurso AWS.

**Estado do Terraform.** Um bucket por conta, `tech-challenge-f4-tfstate-<conta>`, com versionamento,
criptografia (AES256) e bloqueio de acesso público. Uma chave por repositório:

| Repositório | Chave |
|---|---|
| plataforma | `plataforma/terraform.tfstate` |
| os-service | `os-service/terraform.tfstate` |
| execucao-service | `execucao-service/terraform.tfstate` |
| billing-service | `billing-service/terraform.tfstate` |
| auth-lambda | `auth-lambda/terraform.tfstate` |

**Parâmetros no SSM**, todos sob `/tech-challenge-f4/` (`SecureString` usa a chave `alias/aws/ssm`):

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

**Namespaces e componentes no cluster:**

| Namespace | Dono | Conteúdo |
|---|---|---|
| `mensageria` | plataforma | RabbitMQ 4.1 com painel |
| `newrelic` | plataforma | `nri-bundle` (só com licença) |
| `os-service` | os-service | API do OS Service |
| `execucao-service` | execucao-service | API da Execução |
| `billing-service` | billing-service | API do Billing e MongoDB 8.0 em replica set de 1 nó (`emptyDir`, Service `mongo`) |

O MongoDB é lido com `mongodb://mongo.billing-service.svc.cluster.local:27017/?directConnection=true`.
RabbitMQ e MongoDB usam `emptyDir`: o ambiente é efêmero, o driver EBS CSI exigiria uma role IAM própria, e o
outbox de cada serviço republica o que não tiver sido confirmado.

**Exposição.**

| Serviço | NodePort | Listener do NLB | Health check do target group |
|---|---|---|---|
| os-service | 30080 | 80 | `GET /health` |
| execucao-service | 30081 | 8081 | `GET /health` |
| billing-service | 30082 | 8082 | `GET /health` |

**Segredo de cada serviço no cluster.** O pipeline de cada serviço monta, a cada deploy, o Secret
`<servico>-segredos` no namespace do serviço, lendo o SSM:

| Chave | os-service | execucao-service | billing-service |
|---|---|---|---|
| `DATABASE_URL` | `os-service/database_url` | `execucao-service/database_url` | — |
| `MONGO_URL` | — | — | URL do MongoDB do próprio namespace |
| `SECRET_KEY` | `segredos/jwt_secret_key` | idem | idem |
| `RABBITMQ_URL` | `rabbitmq/url` | idem | idem |
| `TOKEN_INTERNO` | `segredos/token_interno` | — | — |
| `NEW_RELIC_LICENSE_KEY` | `newrelic/license_key` | idem | idem |
| `MP_ACCESS_TOKEN`, `MP_EXTERNAL_POS_ID`, `MP_WEBHOOK_SECRET` | — | — | secrets do repositório no GitHub |

**Recursos de cada serviço (`infra/` do repositório):**

| | os-service | execucao-service | billing-service |
|---|---|---|---|
| ECR | `tech-challenge-f4-os-service` | `tech-challenge-f4-execucao-service` | `tech-challenge-f4-billing-service` |
| Banco | RDS PostgreSQL 16 `db.t3.micro`, 20 GB gp2, subnets privadas | idem | MongoDB no cluster (manifesto em `k8s/`) |
| Security group do banco | entrada 5432 só do `cluster/sg_id` | idem | — |
| Senha | `random_password`, publicada em `database_url` | idem | — |

O RDS não tem enhanced monitoring nem Performance Insights e não faz snapshot final
(`skip_final_snapshot = true`), para destruir sem sobras e caber nas restrições do laboratório.

**GitHub.** A variável de repositório `AMBIENTE_ATIVO` ([ADR-013](#decisões-herdadas-da-fase-03)) existe nos
cinco repositórios. Secrets de AWS conforme o modo de autenticação da seção anterior.

---

## 9. Alvos do Makefile

`make` sem argumento lista os alvos que têm descrição (`make help`). Variáveis aceitas na linha de comando:
`AWS_REGION` (padrão `us-east-1`), `GITHUB_OWNER` (padrão: dono do remote `origin`) e `GITHUB_OWNER_ID` (padrão:
`gh api users/<dono>`).

| Alvo | O que faz |
|---|---|
| `help` | Lista os alvos |
| `conta` | Mostra a conta AWS, o perfil e a região em que os comandos vão atuar. Recusa se `AWS_PROFILE` e `AWS_ACCESS_KEY_ID` estiverem vazios |
| `dono` | Confere que o dono dos repositórios e o ID dele no GitHub foram descobertos (depende de `conta`). Usado por `plan`, `up` e `down` |
| `bootstrap` | **Passo zero.** Cria o bucket do estado remoto (`scripts/bootstrap.sh criar`) com versionamento, criptografia e bloqueio de acesso público. Repetir é seguro |
| `bootstrap-destroy` | **Último passo.** Apaga o bucket e todo o histórico de estado. Recusa se algum estado ainda gerencia recurso, e pede a palavra `apagar` |
| `init` | `terraform init` com o bucket e a região desta conta |
| `fmt` | `terraform fmt -recursive` |
| `validate` | `terraform init -backend=false` e `terraform validate`, sem AWS |
| `plan` | `terraform plan` (inicializa antes, se preciso) |
| `up` | **Sobe a plataforma (~15 min); a cobrança começa aqui.** Confere o bucket, inicializa, roda `terraform apply` (pede confirmação), atualiza o kubeconfig e liga `AMBIENTE_ATIVO` nos cinco repositórios |
| `down` | **Desliga o ambiente nos pipelines e destrói a plataforma.** Recusa enquanto existir Lambda ou RDS `tech-challenge-f4*`, e recusa se houver recursos do New Relic no estado sem `NEW_RELIC_API_KEY` exportada. Desliga `AMBIENTE_ATIVO`, roda `terraform destroy` (repete uma vez depois de `limpar-orfas`, se falhar) e limpa órfãos no fim |
| `apply` | Sinônimo de `up` |
| `destroy` | Sinônimo de `down` |
| `limpar-orfas` | Apaga interfaces de rede (`available`) e security groups `eks-cluster-sg-tech-challenge-f4-eks-*` que o plugin de rede do EKS deixa para trás e que impedem a remoção das subnets |
| `github-segredos` | Grava as credenciais AWS (OIDC ou laboratório, conforme a [seção 7](#7-modo-laboratório-aws-academy-e-conta-comum)) nos cinco repositórios e as chaves do New Relic (`NEW_RELIC_LICENSE_KEY`, `NEW_RELIC_API_KEY`, `NEW_RELIC_ACCOUNT_ID`) nesta plataforma, quando exportadas |
| `ambiente-ligar` | `AMBIENTE_ATIVO=true` nos cinco repositórios |
| `ambiente-desligar` | `AMBIENTE_ATIVO=false` nos cinco repositórios |
| `ambiente-status` | Mostra `AMBIENTE_ATIVO` de cada repositório |
| `kubeconfig` | `aws eks update-kubeconfig` para o cluster `tech-challenge-f4-eks` |
| `output` | `terraform output` |
| `status` | `kubectl get nodes -o wide` e `kubectl get pods,svc -n mensageria` |
| `rabbitmq` | `kubectl port-forward` do painel do RabbitMQ para http://localhost:15672 |
| `custo` | Mostra o custo por hora do que fica de pé |
| `local-up` | Sobe RabbitMQ e os bancos da Saga localmente, em docker compose (`docker compose -f local/docker-compose.yml up -d --wait`) |
| `local-down` | Derruba o ambiente local e apaga os volumes (`down -v`) |
| `local-status` | `docker compose ps` do ambiente local |

Os alvos de nuvem (`bootstrap`, `init`, `plan`, `up`, `down`, `github-segredos`, `kubeconfig`) exigem
`AWS_PROFILE` (ou as credenciais no ambiente). Os que falam com o GitHub exigem o `gh` autenticado.

As chaves do New Relic entram no Terraform pelas variáveis `NEW_RELIC_LICENSE_KEY`, `NEW_RELIC_API_KEY`,
`NEW_RELIC_ACCOUNT_ID` e `EMAIL_ALERTAS` do ambiente (o Makefile as repassa como `TF_VAR_*`).

---

## 10. Subir e destruir a solução inteira

### Pré-requisitos

| Ferramenta | Para quê |
|---|---|
| AWS CLI v2 | Todos os alvos de nuvem |
| Terraform 1.10 ou mais novo | Plataforma, bancos e Lambda (o CI usa 1.17.1) |
| `kubectl` | `make kubeconfig`, `make status`, `make rabbitmq` |
| `gh` autenticado (`gh auth login`) | `make up`, `make down`, `make github-segredos`, `make implantar` |
| Docker | Só o ambiente local |
| Python 3.12 e `make` | Só para rodar os testes dos serviços e empacotar a Lambda |

Os cinco repositórios clonados e publicados no seu GitHub, com o mesmo prefixo `tech-challenge-f4-`. O dono é
lido do remote `origin` de cada pasta; para outro dono, use `GITHUB_OWNER=seu-usuario`.

Contas e credenciais externas:

- **SonarQube Cloud:** uma organização e o secret `SONAR_TOKEN` nos quatro repositórios de código (o
  `sonar-project.properties` de cada um define `sonar.organization=pesant0s` e a chave do projeto).
- **New Relic (opcional):** licença (`INGEST-LICENSE`), User key (`NRAK-...`) e ID da conta. Sem elas, o
  cluster sobe sem agente e sem dashboard.
- **Mercado Pago (opcional):** credenciais de teste. Sem elas, o Billing usa o provedor `simulado`.

### Ordem de subida

```mermaid
flowchart LR
  P["plataforma<br/>make bootstrap · make up<br/>make github-segredos"]
  O["os-service<br/>make infra-up · make implantar"]
  E["execucao-service<br/>make infra-up · make implantar"]
  B["billing-service<br/>make infra-up · make implantar"]
  L["auth-lambda<br/>make apply"]
  P --> O
  P --> E
  P --> B
  O --> L
```

Os três serviços sobem em qualquer ordem e em paralelo; a Lambda espera o OS Service estar no ar.

**1. Plataforma** (`tech-challenge-f4-plataforma`)

```bash
export AWS_PROFILE=seu-perfil
make conta               # confere a conta em que vai atuar
make bootstrap           # bucket do estado remoto (uma vez por conta)

# opcional: New Relic
export NEW_RELIC_LICENSE_KEY=... NEW_RELIC_API_KEY=NRAK-... NEW_RELIC_ACCOUNT_ID=... EMAIL_ALERTAS=voce@exemplo.com

make up                  # ~15 min; a cobrança começa aqui; liga AMBIENTE_ATIVO nos cinco repositórios
make github-segredos     # credenciais AWS (e chaves do New Relic) nos repositórios
make status              # nodes Ready e pods do RabbitMQ em Running
```

No AWS Academy: inicie o laboratório, grave as credenciais temporárias num perfil do AWS CLI e exporte
`AWS_PROFILE` com ele. Refaça `make github-segredos` a cada vez que o laboratório for reiniciado.

**2. Secrets opcionais nos repositórios de serviço**

| Repositório | Secret | Efeito |
|---|---|---|
| os-service, execucao-service, billing-service, auth-lambda | `SONAR_TOKEN` | Necessário para o job de qualidade |
| os-service | `ADMIN_PASSWORD` | Senha do usuário `admin`. Sem ele, o pipeline reaproveita a do cluster ou gera uma |
| billing-service | `MP_ACCESS_TOKEN`, `MP_EXTERNAL_POS_ID`, `MP_WEBHOOK_SECRET` | Com `MP_ACCESS_TOKEN`, o pipeline troca o provedor para `mercadopago`. Sem ele, o Billing usa o simulador |

**3. Os três serviços**, em cada pasta (`tech-challenge-f4-os-service`, `tech-challenge-f4-execucao-service`,
`tech-challenge-f4-billing-service`), em qualquer ordem e em paralelo:

```bash
export AWS_PROFILE=seu-perfil
make infra-up            # ECR (e RDS, no OS Service e na Execução); a plataforma precisa estar no ar
make implantar           # aciona o pipeline ci-cd.yml na main
```

O pipeline de cada serviço também aplica a infraestrutura, de forma idempotente; `make infra-up` cria o banco e
o ECR antes do primeiro deploy. O pipeline monta o Secret do serviço a partir do SSM, publica a imagem no ECR,
aplica os manifestos, espera o rollout e roda um teste de fumaça pelo API Gateway.

**4. Lambda** (`tech-challenge-f4-auth-lambda`), depois que o OS Service estiver no ar:

```bash
export AWS_PROFILE=seu-perfil
make apply               # empacota, publica a função e a rota POST /auth/cpf (alternativa: make implantar)
make invoke CPF=...      # testa de ponta a ponta
```

**5. Mercado Pago** (só com o provedor `mercadopago`): cadastre no painel do Mercado Pago a URL do webhook
`<url_api>/billing/webhooks/mercadopago`. A `<url_api>` muda a cada ambiente novo:

```bash
terraform output -raw url_api       # na pasta da plataforma
```

**6. Conferência** (na pasta da plataforma)

```bash
URL=$(terraform output -raw url_api)
curl -s "$URL/health"                # OS Service
curl -s "$URL/billing/openapi.json" | head -c 200
kubectl get pods -A | grep -E 'service|rabbit|mongo'
```

Depois rode a [coleção Postman](#13-coleção-postman) com `newman`.

### Ordem de destruição

A ordem é a inversa. A plataforma e o bucket recusam a destruição enquanto houver recurso dependente vivo.

```bash
# 1. Lambda
cd tech-challenge-f4-auth-lambda      && make destroy

# 2. Serviços (qualquer ordem): ECR e, no OS Service e na Execução, o RDS
cd tech-challenge-f4-billing-service  && make infra-down
cd tech-challenge-f4-execucao-service && make infra-down
cd tech-challenge-f4-os-service       && make infra-down

# 3. Plataforma: desliga AMBIENTE_ATIVO e destrói cluster, rede, gateway e New Relic
cd tech-challenge-f4-plataforma
export NEW_RELIC_API_KEY=NRAK-... NEW_RELIC_ACCOUNT_ID=...   # se o New Relic foi criado
make down

# 4. Último passo: o bucket do estado
make bootstrap-destroy
```

RabbitMQ, MongoDB e os pods dos serviços somem junto com o cluster. `make down` recusa enquanto houver Lambda ou
RDS `tech-challenge-f4*`, e `make bootstrap-destroy` recusa enquanto houver estado com recurso gerenciado.

---

## 11. Custo

`make custo` mostra o que pesa com o cluster de pé:

| Recurso | Por hora |
|---|---|
| EKS control plane | US$ 0,100 (suporte padrão; no estendido, US$ 0,60) |
| 3 × `t3.medium` On-Demand | US$ 0,125 |
| NLB interno | US$ 0,023 |
| EBS dos nodes | US$ 0,008 |
| **Total ligado** | **~US$ 0,26/h**, fora os RDS dos serviços |

Os dois RDS (`db.t3.micro`) somam cerca de US$ 0,03/h ([ADR-020](docs/adr/ADR-020-banco-por-servico.md)), o que
leva o ambiente completo a cerca de **US$ 0,29/h**. API Gateway, ECR, Lambda e SSM têm custo desprezível neste
volume. O RabbitMQ e o MongoDB rodam nos próprios nodes, sem cobrança à parte.

Defina um **AWS Budget** com alertas. Todo recurso leva a tag `Project = tech-challenge-f4`, então o Cost
Explorer isola o gasto.

---

## 12. Ambiente local

Para desenvolver e testar sem nuvem e sem custo ([ADR-024](docs/adr/ADR-024-ambientes.md)). Só exige Docker.

```bash
make local-up        # sobe e espera todos ficarem saudáveis
make local-status
make local-down      # derruba e apaga os volumes
```

`make local-up` roda `docker compose -f local/docker-compose.yml up -d --wait` (projeto `oficina`).

| Componente | Imagem | Endereço | Credenciais | Limite de memória |
|---|---|---|---|---|
| RabbitMQ | `rabbitmq:4.1-management-alpine` | `amqp://localhost:5672` · painel http://localhost:15672 | `oficina` / `oficina` | 512 MB |
| PostgreSQL do OS Service | `postgres:16-alpine` | `localhost:5433`, banco `os` | `os` / `os` | 256 MB |
| PostgreSQL da Execução | `postgres:16-alpine` | `localhost:5434`, banco `execucao` | `execucao` / `execucao` | 256 MB |
| MongoDB do Billing | `mongo:8.0` | `mongodb://localhost:27017/?replicaSet=rs0` | sem autenticação | 512 MB |

- O MongoDB sobe como **replica set `rs0` de um nó**, porque as transações do outbox exigem replica set. O
  health check inicia o replica set na primeira vez e depois só confirma que há primário.
- Os bancos e o broker têm volume nomeado (`rabbitmq`, `postgres-os`, `postgres-execucao`, `mongo`): os dados
  sobrevivem a um `docker compose stop`, e `make local-down` os apaga.
- As exchanges e filas não são criadas aqui: cada serviço declara as suas ao iniciar
  ([`docs/contratos`](docs/contratos/README.md)).

Variáveis para apontar um serviço rodando na máquina para esse ambiente (a `SECRET_KEY`, com 32 caracteres ou
mais, precisa ser a mesma nos três serviços e na Lambda):

| Serviço | Variáveis |
|---|---|
| os-service | `DATABASE_URL=postgresql://os:os@localhost:5433/os` · `RABBITMQ_URL=amqp://oficina:oficina@localhost:5672/%2F` · `SECRET_KEY` · `TOKEN_INTERNO` |
| execucao-service | `DATABASE_URL=postgresql://execucao:execucao@localhost:5434/execucao` · `RABBITMQ_URL=amqp://oficina:oficina@localhost:5672/%2F` · `SECRET_KEY` |
| billing-service | `MONGO_URL=mongodb://localhost:27017/?replicaSet=rs0` · `RABBITMQ_URL=amqp://oficina:oficina@localhost:5672/%2F` · `SECRET_KEY` |

Sem `RABBITMQ_URL`, a mensageria de um serviço não sobe: a API atende e as mensagens ficam paradas no outbox.
Cada serviço também tem o próprio `docker-compose.yml` e `make up` (README de cada repositório).

---

## 13. Coleção Postman

Em [`docs/postman/`](docs/postman/):

| Arquivo | Conteúdo |
|---|---|
| `oficina-fase04.postman_collection.json` | Coleção "Oficina - Fase 04 - Saga pelos três serviços": 39 requisições e 85 chamadas `pm.test` |
| `local.postman_environment.json` | Ambiente "Oficina Fase 04 - local" |

A coleção percorre a Saga pelo OS Service, a Execução, o Billing e a Lambda de CPF:

| Pasta | O que cobre |
|---|---|
| 1. Preparação | Token de funcionário; serviço e peça (estoque 10) no catálogo; cliente e veículo; token do cliente pela Lambda |
| 2. Caminho feliz | Abre a OS (1 serviço e 2 peças), espera o orçamento, aprova como cliente, espera o QR, aprova o pagamento no simulador, espera `NA_FILA`, chama a fila, inicia o reparo, finaliza, entrega e confere o estoque (8 em estoque, 0 reservada) |
| 3. Compensação - orçamento rejeitado | Rejeita o orçamento e confere OS `NEGADA`, Saga compensada e reserva devolvida |
| 4. Compensação - cancelamento de OS já paga | Cancela a OS logo após o pagamento e confere OS `CANCELADA`, pagamento `REEMBOLSADO` no Billing e reserva devolvida |
| 5. Regras de acesso | Outro cliente não vê o orçamento alheio; listar OS sem token é negado; cliente não usa o simulador; a Lambda rejeita CPF inválido |

Variáveis do ambiente: `osUrl`, `execucaoUrl`, `billingUrl`, `authUrl`, `adminUsuario` e `adminSenha`. As demais
(`tokenFuncionario`, `osId`, `pagamentoId` etc.) a própria coleção preenche durante a execução.

### Rodar no Postman

Importe a coleção e o ambiente. Ajuste as quatro URLs e a senha do `admin`.

### Rodar no newman

```bash
cd tech-challenge-f4-plataforma

# Local: as URLs do ambiente são http://localhost:8001 a :8004 (os, execução, billing, Lambda)
npx -y newman@6 run docs/postman/oficina-fase04.postman_collection.json \
  -e docs/postman/local.postman_environment.json

# Nuvem: as quatro URLs são o endpoint do API Gateway
URL=$(terraform output -raw url_api)
SENHA=$(kubectl -n os-service get secret os-service-segredos -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d)
npx -y newman@6 run docs/postman/oficina-fase04.postman_collection.json \
  -e docs/postman/local.postman_environment.json \
  --env-var "osUrl=$URL" --env-var "execucaoUrl=$URL" \
  --env-var "billingUrl=$URL" --env-var "authUrl=$URL" \
  --env-var "adminSenha=$SENHA"
```

Pontos de atenção:

- As etapas "Aprovar o pagamento no simulador" usam a rota `POST /billing/simulador/pagamentos/{id}/aprovar`, que
  só existe com `PAGAMENTO_PROVEDOR=simulado` (a rota responde 404 "Simulador desligado" com o provedor
  `mercadopago`). Na nuvem, a coleção só passa de ponta a ponta com o Billing no provedor simulado, isto é, sem o
  secret `MP_ACCESS_TOKEN` no repositório do Billing.
- As requisições de espera repetem a consulta (até 40 tentativas, variável `tentativas`) até a Saga avançar; a conciliação do Billing roda a
  cada `CONCILIACAO_SEGUNDOS` (15 s por padrão).
- Localmente, a Lambda de CPF (`authUrl`) precisa estar acessível na URL configurada; o repositório da Lambda não
  traz um servidor local, e o [ADR-024](docs/adr/ADR-024-ambientes.md) prevê o LocalStack para isso. As portas
  8001 a 8004 do ambiente são o padrão da coleção: ajuste com `--env-var` para as portas em que subiu os
  serviços.

---

## 14. Contrato AsyncAPI

[`docs/contratos/asyncapi.yaml`](docs/contratos/asyncapi.yaml) (AsyncAPI 3.0) é a fonte de verdade das
mensagens da Saga; [`docs/contratos/README.md`](docs/contratos/README.md) é o resumo para leitura. Quando os dois
divergirem, vale o `asyncapi.yaml`. Validação local:

```bash
npx -y @asyncapi/cli@2.16.4 validate docs/contratos/asyncapi.yaml --fail-severity=error
```

O documento é escrito do ponto de vista do OS Service (orquestrador): ele envia 7 comandos e recebe 17 eventos.

**Topologia no RabbitMQ**

| Exchange | Tipo | Quem publica | Para quê |
|---|---|---|---|
| `oficina.comandos` | topic | OS Service | Pedidos do orquestrador aos participantes |
| `oficina.eventos` | topic | Execução e Billing | Resultado dos comandos e mudanças de estado |
| `oficina.dlx` | topic | RabbitMQ | Destino das mensagens que esgotaram as tentativas |

| Fila | Ligada a | Chave | Consumidor |
|---|---|---|---|
| `execucao-service.comandos` | `oficina.comandos` | `execucao.#` | Execução |
| `billing-service.comandos` | `oficina.comandos` | `billing.#` | Billing |
| `os-service.eventos` | `oficina.eventos` | `execucao.#` e `billing.#` | OS Service |
| `<fila>.dlq` | `oficina.dlx` | nome da fila de origem | ninguém (inspeção) |

Todas as exchanges são duráveis e as filas são quorum queues. Cada serviço declara as exchanges em que publica e
as filas que consome ao iniciar; a declaração é idempotente, então a ordem de subida não importa.

**Comandos** (OS Service → participantes, exchange `oficina.comandos`)

| Mensagem | Chave de roteamento | Destino | Payload |
|---|---|---|---|
| `ReservarPecas` | `execucao.reservar-pecas` | Execução | `itens[]` (`tipo`, `item_id`, `quantidade`) |
| `LiberarReserva` | `execucao.liberar-reserva` | Execução | `motivo` |
| `EnfileirarOS` | `execucao.enfileirar-os` | Execução | `veiculo_id` |
| `GerarOrcamento` | `billing.gerar-orcamento` | Billing | `cliente` (`id`, `nome`, `email`, `telefone`), `itens[]` precificados, `valor_total` |
| `Cobrar` | `billing.cobrar` | Billing | `orcamento_id` |
| `CancelarOrcamento` | `billing.cancelar-orcamento` | Billing | `motivo` |
| `Reembolsar` | `billing.reembolsar` | Billing | `motivo` |

**Eventos** (participantes → OS Service, exchange `oficina.eventos`)

| Mensagem | Chave de roteamento | Publicado por |
|---|---|---|
| `PecasReservadas`, `ReservaRecusada`, `ReservaLiberada` | `execucao.pecas-reservadas`, `execucao.reserva-recusada`, `execucao.reserva-liberada` | Execução |
| `OSEnfileirada`, `EnfileiramentoRecusado` | `execucao.os-enfileirada`, `execucao.enfileiramento-recusado` | Execução |
| `DiagnosticoIniciado`, `ExecucaoIniciada`, `ExecucaoFinalizada` | `execucao.diagnostico-iniciado`, `execucao.execucao-iniciada`, `execucao.execucao-finalizada` | Execução |
| `OrcamentoGerado`, `OrcamentoAprovado`, `OrcamentoRejeitado`, `OrcamentoCancelado` | `billing.orcamento-gerado`, `billing.orcamento-aprovado`, `billing.orcamento-rejeitado`, `billing.orcamento-cancelado` | Billing |
| `CobrancaCriada`, `PagamentoConfirmado`, `PagamentoRecusado` | `billing.cobranca-criada`, `billing.pagamento-confirmado`, `billing.pagamento-recusado` | Billing |
| `PagamentoReembolsado`, `ReembolsoFalhou` | `billing.pagamento-reembolsado`, `billing.reembolso-falhou` | Billing |

**Envelope.** Toda mensagem tem o mesmo corpo JSON; o conteúdo específico fica em `payload`.

```json
{
  "message_id": "0d6f3c1e-…",
  "tipo": "ReservarPecas",
  "versao": 1,
  "saga_id": "7a1b…",
  "os_id": "c93e…",
  "ocorrido_em": "2026-11-12T15:00:00Z",
  "origem": "os-service",
  "payload": { "itens": [ { "tipo": "PECA", "item_id": "…", "quantidade": 2 } ] }
}
```

| Propriedade AMQP | Valor |
|---|---|
| `message_id` | igual ao `message_id` do corpo (chave de idempotência do consumidor) |
| `type` | igual ao `tipo` |
| `correlation_id` | `saga_id` |
| `content_type` | `application/json` |
| `delivery_mode` | 2 (persistente) |
| cabeçalhos | `traceparent`, `tracestate` e `newrelic`, para o rastreamento distribuído (não vão no corpo) |

Dinheiro trafega como texto com duas casas (`"150.00"`). Datas em RFC 3339, UTC. CPF e CNPJ não trafegam: o
Billing confere o titular pelo `cliente_id` do JWT. Motivos de compensação (`motivo`): `ORCAMENTO_REJEITADO`,
`ORCAMENTO_EXPIRADO`, `PAGAMENTO_RECUSADO`, `PAGAMENTO_EXPIRADO`, `ENFILEIRAMENTO_RECUSADO`, `PRAZO_ESGOTADO` e
`CANCELADA_PELA_OFICINA`.

---

## 15. Workflows da plataforma

Em [`.github/workflows/`](.github/workflows/). A `main` é protegida: só recebe código por Pull Request, com o
check `Formatação e validação` obrigatório (inclusive para administradores). O trabalho acontece na `develop`.

### `terraform.yml` · "Terraform"

| Item | Valor |
|---|---|
| Gatilhos | `push` e `pull_request` na `main`; `workflow_dispatch` |
| Concorrência | grupo `terraform-f4-plataforma`, sem cancelar execução em andamento |
| Variáveis | `AWS_REGION=us-east-1`, `TF_IN_AUTOMATION=true`, `TF_VERSION=1.17.1`, `TF_VAR_org_github` e `TF_VAR_id_dono_github` (dono do repositório e ID) |
| Permissões | `contents: read` (o job `aplicar` acrescenta `id-token: write`) |

| Job | Nome na tela | Quando roda | O que faz |
|---|---|---|---|
| `validar` | Formatação e validação | sempre | `terraform fmt -check -recursive -diff`, `terraform init -backend=false` e `terraform validate`. **É o check obrigatório da `main`** |
| `ambiente-desligado` | Plan e apply não executados | `push` ou execução manual, com `AMBIENTE_ATIVO` diferente de `true` | Escreve no resumo da execução que o cluster está desligado. Job pulado não é falha |
| `aplicar` | Plan e apply | `push` ou execução manual na `main`, com `AMBIENTE_ATIVO=true` | Autentica na AWS, inicializa o estado remoto da conta, roda `terraform plan -out=tfplan` e `terraform apply tfplan` |

Autenticação do job `aplicar`: com o secret `AWS_ROLE_ARN`, assume a role por OIDC; se a role não puder ser
assumida, o job falha com uma mensagem explicando as causas prováveis (ambiente destruído sem `make down`, ou
secret desatualizado). Sem `AWS_ROLE_ARN`, usa as credenciais temporárias do laboratório.

Secrets e variáveis usados: `AWS_ROLE_ARN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`,
`NEW_RELIC_LICENSE_KEY`, `NEW_RELIC_API_KEY`, `NEW_RELIC_ACCOUNT_ID` (secrets) e `AMBIENTE_ATIVO`,
`EMAIL_ALERTAS` (variáveis).

Nenhum pipeline recria o cluster do zero: o primeiro `apply` é sempre local (`make up`), porque a role que o
pipeline assume nasce nele (conta comum) e porque ligar a cobrança é sempre uma ação humana.

### `contratos.yml` · "Contratos"

| Item | Valor |
|---|---|
| Gatilhos | `push` e `pull_request` em `develop` e `main`, só quando mudam `docs/contratos/**` ou o próprio workflow |
| Job | `asyncapi` · "Validar AsyncAPI" |
| Passo | Node 22 e `npx -y @asyncapi/cli@2.16.4 validate docs/contratos/asyncapi.yaml --fail-severity=error` |

### O ambiente efêmero e `AMBIENTE_ATIVO`

O ambiente AWS só existe durante as sessões de trabalho, porque o control plane cobra por hora. A variável de
repositório `AMBIENTE_ATIVO`, nos cinco repositórios, diz ao pipeline em que estado ele está.

| Evento | `AMBIENTE_ATIVO` | O que acontece (em todos os repositórios) |
|---|---|---|
| Pull Request | qualquer | Só o que não precisa de AWS: testes, validação, qualidade, build e boot da imagem, empacotamento |
| `push` na `main` ou execução manual | `true` | Tudo o que não precisa de AWS, mais o deploy (imagem no ECR, manifestos no EKS, teste de fumaça; na plataforma, `plan` e `apply`) |
| `push` na `main` ou execução manual | ausente ou `false` | Só a parte sem AWS; o deploy aparece como **pulado**, com o motivo no resumo |

`make up` liga a variável ao final; `make down` a desliga **antes** de destruir. Uma falha de autenticação com a
variável em `true` continua vermelha: a chave não mascara erro.

---

## 16. Observabilidade

Tudo é código Terraform (`newrelic.tf` e `observabilidade.tf`), criado e destruído junto com o cluster.

### Como os dados chegam

| Sinal | De onde vem |
|---|---|
| CPU, memória, réplicas do HPA e eventos do cluster | `nri-bundle` (Helm), com `kube-state-metrics`, `nri-kube-events` e `newrelic-logging` habilitados |
| Logs JSON dos pods | `nri-bundle`, a partir do stdout. O JSON de cada serviço (`LOG_FORMAT=json`) vira atributos consultáveis, como `saga_id`, `os_id`, `evento`, `estado`, `logger` e `level` |
| APM e traces | Agente Python do New Relic na imagem de cada serviço, ativo quando há licença |
| Traces através do RabbitMQ | Os cabeçalhos AMQP `traceparent`, `tracestate` e `newrelic` carregam o contexto; o consumo de mensagens aparece como transações `OtherTransaction/Message/RabbitMQ/*` |
| Gateway | Access log JSON no CloudWatch (`/aws/apigateway/tech-challenge-f4`, 7 dias): `requestId`, `ip`, `requestTime`, `httpMethod`, `routeKey`, `status`, `responseLength`, `latenciaMs`, `erroIntegracao`. O `requestId` é propagado como `x-request-id` |
| Plano de controle do EKS | Logs `api` e `audit` no CloudWatch (`/aws/eks/tech-challenge-f4-eks/cluster`, 7 dias) |
| Lambda | Logs no CloudWatch. As métricas (invocações, erros) chegam ao New Relic por polling do CloudWatch, **só fora do laboratório** |
| Uptime | Monitor sintético `tech-challenge-f4-api-health`: `GET <url_api>/health` a cada 5 minutos, a partir de `US_EAST_1` |

O agente Python não encaminha logs (`NEW_RELIC_APPLICATION_LOGGING_FORWARDING_ENABLED=false`), para não duplicar
cada linha: o `nri-bundle` já coleta o stdout.

Sem a licença (`newrelic_license_key` vazia), o `nri-bundle` não é instalado, os serviços sobem sem agente e o
SSM recebe `desligado` em `newrelic/license_key`. Sem a User key e o ID da conta, nada de dashboard, alerta e
monitor é criado.

### Dashboard "Tech Challenge · Oficina"

Quatro páginas, 23 widgets.

**Saga** (10 widgets)

| Widget | Tipo | O que mostra |
|---|---|---|
| Sagas iniciadas (24h) | billboard | Sagas distintas (`saga_id`) com gatilho `OSAberta` |
| Concluídas (24h) | billboard | Sagas no estado `CONCLUIDA` |
| Compensadas (24h) | billboard | Sagas no estado `COMPENSADA` |
| Falha na compensação (24h) | billboard | Sagas no estado `FALHA_NA_COMPENSACAO` |
| Sagas desfeitas por motivo | pizza | Sagas `COMPENSADA` por `motivo` |
| Passos da Saga por gatilho | linha | Linhas de log da Saga por `gatilho`, ao longo do tempo |
| Comandos atendidos pela Execução e pelo Billing | barras | Eventos `comando_processado` por `tipo` |
| Mensagens repetidas, descartadas ou com falha | linha | Eventos `mensagem_repetida`, `saga_evento_descartado`, `mensagem_invalida`, `mensagem_sem_saga`, `falha_no_consumo` e `publicacao_recusada` |
| Consumo de mensagens por serviço (rastreamento distribuído) | linha | Transações `OtherTransaction/Message/RabbitMQ/*` por aplicação |
| Linha do tempo das Sagas | tabela | `saga_id`, `os_id`, `gatilho`, `passo`, `estado`, `motivo`, `comandos` da última hora |

**Ordens de serviço** (4 widgets)

| Widget | Tipo | O que mostra |
|---|---|---|
| OS abertas hoje | billboard | Eventos `os_status` sem status anterior, desde o início do dia |
| Volume diário de OS | linha | OS abertas por dia, 7 dias |
| Tempo médio por status (minutos) | barras | `segundos_no_status_anterior` médio em `EM_DIAGNOSTICO`, `EM_EXECUCAO` e `FINALIZADA` |
| Últimas mudanças de status | tabela | `os_id`, status anterior e novo, tempo no status anterior, `correlation_id` |

**API e integrações** (5 widgets)

| Widget | Tipo | O que mostra |
|---|---|---|
| Latência da API (ms) | linha | p95 e média das transações web, por aplicação |
| Uptime em 24h (monitor externo) | billboard | Percentual de checks `SUCCESS` do monitor |
| Healthcheck externo (ms) | linha | Duração média do check sintético |
| Erros por componente | linha | Logs `ERROR` por `logger` |
| Lambda de autenticação | linha | Invocações e erros da função; depende da integração AWS, então fica vazio no laboratório |

**Kubernetes** (4 widgets)

| Widget | Tipo | O que mostra |
|---|---|---|
| CPU por pod (cores) | linha | Nos namespaces `os-service`, `execucao-service`, `billing-service` e `mensageria` |
| Memória por pod (MiB) | linha | Idem |
| Réplicas do HPA | linha | Réplicas atuais e desejadas por namespace |
| Reinícios de container na última hora | billboard | Soma de `restartCountDelta` |

### Alertas

Política **"Tech Challenge · Oficina"** (`incident_preference = PER_CONDITION`). Cada condição é estática: abre
incidente quando a contagem passa de 0 na janela. As consultas varrem todos os eventos da janela e contam quantos
falharam, em vez de buscar só as falhas: assim há sinal (valor 0) mesmo quando está tudo bem, e o incidente
**fecha sozinho** na recuperação (`fill_value = 0`, expiração de 3 janelas fecha o incidente).

| Condição | Consulta | Janela |
|---|---|---|
| Falha no processamento de ordens de serviço | 5xx ou erro nos logs do `oficina.http` em `/atendimento/os*` | 60 s |
| Saga parada em falha na compensação | Logs `saga` com `estado = FALHA_NA_COMPENSACAO` | 60 s |
| Falha ao processar mensagens da Saga | Logs do `oficina.mensageria` com `falha_no_consumo`, `mensagem_sem_saga` ou `mensagem_invalida` | 300 s |
| API fora do ar para o monitor externo | Check sintético com resultado diferente de `SUCCESS` | 300 s |

Com `email_alertas` definido, os incidentes chegam por e-mail (destino, canal e workflow do New Relic); sem ele,
ficam em **Alerts → Issues**. Entre o `make up` e o primeiro deploy do OS Service o monitor falha e o alerta de
API fora do ar abre um incidente: é esperado, e fecha sozinho quando a API responde.

### Integração AWS (só fora do laboratório)

Com as chaves do New Relic, o Terraform cria a role `tech-challenge-f4-newrelic` (política `ReadOnlyAccess`,
confiança na conta de integrações do New Relic com o ID da conta como `ExternalId`) e liga a integração de Lambda
por polling a cada 300 s em `us-east-1`.

### Variáveis

| Variável | Para quê | Vazia |
|---|---|---|
| `newrelic_license_key` | Instala o `nri-bundle` | Cluster sobe sem agente |
| `newrelic_api_key` · `newrelic_account_id` | Dashboard, alertas, monitor e integração AWS | Nada disso é criado |
| `newrelic_regiao` | `US` (padrão) ou `EU` | — |
| `email_alertas` | Destino dos alertas | Incidentes só no painel |

A User key (tipo `USER`, começa com `NRAK-`) e o ID da conta ficam em **API keys**, no New Relic. Para conta na
região EU, use `TF_VAR_newrelic_regiao=EU`.

---

## 17. Validação em nuvem

O ensaio completo foi feito na AWS Academy (`us-east-1`), com 3 nós `t3.medium`:

- Fluxo completo com **pagamento real** pelo aplicativo do Mercado Pago (conta compradora de teste), da abertura
  da OS até `ENTREGUE`.
- **QR vencido** compensado: a Saga desfez o orçamento e a reserva.
- **Cancelamento com o pagamento chegando no meio**: terminou com o reembolso em `refunded` no Mercado Pago.
- **Mensagens esperaram no RabbitMQ** com o Billing em 0 réplicas e foram processadas quando ele voltou.
- **Traces no New Relic atravessando os três serviços pela fila**.
- **Capacidade:** nós com 41% a 48% de memória; pods dos serviços entre 190 e 225 MiB.

---

## 18. Decisões arquiteturais

Em [`docs/adr/`](docs/adr/) e [`docs/rfc/`](docs/rfc/):

| Documento | Decisão |
|---|---|
| [RFC-001](docs/rfc/RFC-001-nuvem.md) | Escolha da nuvem: AWS, comparada com Azure e Google Cloud, e como o custo é contido |
| [ADR-017](docs/adr/ADR-017-divisao-em-microsservicos.md) | Três microsserviços, divididos pelas áreas da oficina |
| [ADR-018](docs/adr/ADR-018-saga-orquestrada.md) | Saga orquestrada, com o orquestrador no OS Service |
| [ADR-019](docs/adr/ADR-019-rabbitmq.md) | Mensageria com RabbitMQ, dentro do cluster |
| [ADR-020](docs/adr/ADR-020-banco-por-servico.md) | Um banco por serviço: PostgreSQL no OS e na Execução, MongoDB no Billing |
| [ADR-021](docs/adr/ADR-021-outbox-e-idempotencia.md) | Outbox transacional na publicação e consumo idempotente |
| [ADR-022](docs/adr/ADR-022-lambda-consulta-o-os-service.md) | A Lambda de CPF consulta o OS Service, e não o banco dele |
| [ADR-023](docs/adr/ADR-023-mercado-pago.md) | Cobrança pelo Mercado Pago com QR Code dinâmico, atrás de uma porta |
| [ADR-024](docs/adr/ADR-024-ambientes.md) | Desenvolvimento local com docker compose, entrega na AWS |

### Decisões herdadas da Fase 03

Continuam valendo e aparecem nos comentários do Terraform.

| ADR | Decisão | Onde |
|---|---|---|
| ADR-002 | **Sem NAT Gateway.** As subnets privadas não têm rota para a internet; os nodes ficam nas públicas. Economiza o custo por hora do NAT, e a Lambda e os bancos não saem da VPC | `rede.tf` |
| ADR-005 | **O NLB é do Terraform, não do Kubernetes.** Evita a dependência circular entre o gateway (precisa do ARN do listener) e o deploy (precisa do gateway). O alvo é o auto scaling group dos nodes; cada serviço é `NodePort` em porta fixa, e o `kube-proxy` encaminha ao pod. As portas 30080, 30081 e 30082 são contrato entre este repositório e os serviços | `exposicao.tf` |
| ADR-007 | **Autenticação do CI por OIDC, sem chave estática**, restrita à `main` dos cinco repositórios (conta comum). O EKS separa autenticação de autorização: sem a access entry e a associação de política, o pipeline recebe `Unauthorized` mesmo com credenciais válidas | `oidc_github.tf` |
| ADR-008 | **O `metrics-server` é addon do EKS**, pré-requisito do HPA: sem ele o HPA fica em `<unknown>/70%` e nunca escala. Não há Cluster Autoscaler; o máximo de 4 nodes vale para escala manual | `eks.tf` |
| ADR-013 | **Ambiente efêmero com uma chave de estado no GitHub** (`AMBIENTE_ATIVO`), para que os pipelines não fiquem vermelhos com o ambiente desligado e um merge não religue a cobrança sem ninguém perceber ([seção 15](#o-ambiente-efêmero-e-ambiente_ativo)) | `.github/workflows/`, `scripts/github.sh` |
| ADR-014 | **Observabilidade como código.** Dashboard, alertas, monitor de uptime e coleta das métricas da Lambda são recursos Terraform, criados e destruídos junto com o cluster: quem reproduz o ambiente recebe o mesmo painel e os mesmos alertas, e nenhum painel sobra apontando para um ambiente que já não existe | `observabilidade.tf` |

Os nodes da Fase 04 são `On-Demand`: o laboratório não permite Spot, que era o padrão da Fase 03.

---

## 19. Limitações conhecidas

| Limitação | Efeito e como contornar |
|---|---|
| **Migrations simultâneas na subida.** As duas réplicas de cada serviço rodam as migrations do Alembic ao subir | Num banco vazio, uma das réplicas pode reiniciar uma vez (`DuplicateTable alembic_version`). A segunda subida passa |
| **RabbitMQ e MongoDB em `emptyDir`.** Os dados somem se o pod for recriado | O outbox de cada serviço republica o que não foi confirmado. Não há persistência entre execuções do ambiente (aceitável: o ambiente é efêmero, [ADR-019](docs/adr/ADR-019-rabbitmq.md) e [ADR-020](docs/adr/ADR-020-banco-por-servico.md)) |
| **Webhook do Mercado Pago por ambiente.** A URL do API Gateway muda a cada ambiente novo | Cadastre `<url_api>/billing/webhooks/mercadopago` no painel do Mercado Pago a cada subida. Sem o webhook, a conciliação periódica (a cada 15 s) confirma o pagamento do mesmo jeito, só com mais espera |
| **Versão do Terraform no CI.** O workflow `terraform.yml` fixa `TF_VERSION=1.17.1` | O estado remoto guarda a versão do Terraform que o gravou, e o Terraform não lê estado gravado por versão mais nova que a sua. Se o `make up` for feito com um Terraform mais novo que 1.17.1, o job `Plan e apply` falha até que `TF_VERSION` seja atualizado para a versão usada no `make up` (ou o `make up` seja feito com a 1.17.1) |
| **Credenciais do laboratório expiram.** Os pipelines usam as credenciais temporárias gravadas nos repositórios | Rode `make github-segredos` de novo a cada vez que o laboratório for iniciado |
| **Sessão do laboratório retomada com o cluster no ar.** Quando a sessão do AWS Academy expira e é iniciada de novo, os nodes voltam sem IP público, o kubelet não alcança as APIs da AWS e os nodes ficam `NotReady` | Substitua cada instância pelo Auto Scaling Group (`aws autoscaling terminate-instance-in-auto-scaling-group --instance-id <id> --no-should-decrement-desired-capacity`); os nodes novos entram `Ready` em poucos minutos e os pods voltam sozinhos. Para não depender disso, destrua o ambiente na mesma sessão em que ele foi usado |
| **Sem métricas da Lambda no New Relic no laboratório.** A integração AWS exige uma role própria | O widget "Lambda de autenticação" fica vazio; os logs da função continuam no CloudWatch |
| **Sem snapshot final dos RDS** (`skip_final_snapshot = true`) | Destruir os repositórios de serviço apaga os dados |
| **Sem Cluster Autoscaler** | O HPA escala os pods, não os nodes; o máximo de 4 nodes vale para escala manual |
| **Um replica set de um nó e um broker de uma réplica** | Não há alta disponibilidade do RabbitMQ nem do MongoDB; o ambiente é de demonstração |
| **O gateway não valida o JWT** | A validação é dos serviços; um serviço sem a `SECRET_KEY` correta rejeita todo token |

---

## 20. Estrutura do repositório

```
.
├── Makefile                  alvos de operação (seção 9)
├── versions.tf               versão do Terraform, providers e backend S3
├── providers.tf              aws, helm, kubernetes e newrelic
├── variables.tf              variáveis de entrada
├── outputs.tf                saídas (url_api, nome_cluster, ...)
├── rede.tf                   VPC, subnets e rotas
├── laboratorio.tf            detecção do AWS Academy
├── iam_eks.tf                roles do cluster e dos nodes (conta comum)
├── eks.tf                    cluster, nodes e addons
├── exposicao.tf              NLB, VPC Link e API Gateway
├── mensageria.tf             RabbitMQ no cluster
├── segredos.tf               segredos compartilhados
├── ssm_contrato.tf           contrato publicado no SSM
├── oidc_github.tf            OIDC e role de deploy (conta comum)
├── newrelic.tf               agente do New Relic (Helm)
├── observabilidade.tf        dashboard, alertas e monitor
├── terraform.tfvars.example  modelo de variáveis
├── .terraform.lock.hcl       versões fixadas dos providers
├── local/
│   └── docker-compose.yml    ambiente local da Saga
├── scripts/
│   ├── bootstrap.sh          cria e apaga o bucket do estado
│   └── github.sh             liga, desliga e lista AMBIENTE_ATIVO; grava secrets
├── .github/workflows/
│   ├── terraform.yml         validação, plan e apply
│   └── contratos.yml         validação do AsyncAPI
└── docs/
    ├── adr/                  ADR-017 a ADR-024
    ├── rfc/                  RFC-001 (nuvem)
    ├── arquitetura/          diagramas: visao-geral e saga (.mmd, .svg, .png)
    ├── contratos/            asyncapi.yaml e resumo
    ├── infraestrutura/       contrato.md
    └── postman/              coleção e ambiente local
```

### Scripts

| Script | Uso | Comportamento |
|---|---|---|
| `scripts/bootstrap.sh criar <bucket> <região>` | `make bootstrap` | Cria o bucket com versionamento, criptografia AES256 e bloqueio de acesso público; se já existe, não faz nada |
| `scripts/bootstrap.sh destruir <bucket> <região>` | `make bootstrap-destroy` | Recusa se algum `.tfstate` ainda gerencia recurso; pede a palavra `apagar`; remove todas as versões e marcadores e apaga o bucket |
| `scripts/github.sh ligar` · `desligar` · `status` | `make ambiente-*`, `make up`, `make down` | Define, zera ou lista a variável `AMBIENTE_ATIVO` nos cinco repositórios, com `gh` |
| `scripts/github.sh segredos` | `make github-segredos` | Grava credenciais AWS e chaves do New Relic ([seção 7](#7-modo-laboratório-aws-academy-e-conta-comum)) |
