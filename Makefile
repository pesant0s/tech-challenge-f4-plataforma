.DEFAULT_GOAL := help
.PHONY: help conta dono bootstrap bootstrap-destroy init fmt validate plan up down apply destroy limpar-orfas output kubeconfig status rabbitmq custo github-segredos ambiente-ligar ambiente-desligar ambiente-status local-up local-down local-status

AWS_REGION ?= us-east-1
export AWS_REGION

CONTA   = $(shell aws sts get-caller-identity --query Account --output text)
BUCKET  = tech-challenge-f4-tfstate-$(CONTA)
CLUSTER = tech-challenge-f4-eks
# Delimitador `|` no sed: num Makefile, `#` abriria um comentário.
GITHUB_OWNER ?= $(shell git config --get remote.origin.url 2>/dev/null | sed -E 's|^.*github\.com[:/]([^/]+)/.*$$|\1|')
export GITHUB_OWNER
GITHUB_OWNER_ID ?= $(shell gh api users/$(GITHUB_OWNER) --jq .id 2>/dev/null)
TF_VARS = -var "org_github=$(GITHUB_OWNER)" -var "id_dono_github=$(GITHUB_OWNER_ID)"
# Chaves do New Relic pelas mesmas variáveis que o github-segredos grava; um terraform.tfvars ainda prevalece.
TF_VAR_newrelic_license_key ?= $(NEW_RELIC_LICENSE_KEY)
TF_VAR_newrelic_api_key ?= $(NEW_RELIC_API_KEY)
TF_VAR_newrelic_account_id ?= $(NEW_RELIC_ACCOUNT_ID)
TF_VAR_email_alertas ?= $(EMAIL_ALERTAS)
export TF_VAR_newrelic_license_key TF_VAR_newrelic_api_key TF_VAR_newrelic_account_id TF_VAR_email_alertas

help: ## Lista os alvos
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

conta: ## Mostra em qual conta AWS os comandos vão atuar
	@test -n "$$AWS_PROFILE$$AWS_ACCESS_KEY_ID" || { echo "Defina AWS_PROFILE com a conta que vai receber a plataforma."; exit 1; }
	@echo "Conta AWS: $(CONTA) · perfil: $${AWS_PROFILE:-credenciais do ambiente} · região: $(AWS_REGION)"

dono: conta
	@test -n "$(GITHUB_OWNER)" || { echo "Dono dos repositórios desconhecido: rode com GITHUB_OWNER=seu-usuario."; exit 1; }
	@test -n "$(GITHUB_OWNER_ID)" || { echo "ID do dono no GitHub não encontrado: confira o gh auth status."; exit 1; }

bootstrap: conta ## Passo zero: cria o bucket do estado remoto
	@./scripts/bootstrap.sh criar "$(BUCKET)" "$(AWS_REGION)"

bootstrap-destroy: conta ## Último passo: apaga o bucket do estado; recusa se houver recurso vivo
	@./scripts/bootstrap.sh destruir "$(BUCKET)" "$(AWS_REGION)"

init: conta ## Inicializa o Terraform com o estado desta conta
	terraform init -backend-config="bucket=$(BUCKET)" -backend-config="region=$(AWS_REGION)"

fmt: ## Formata os arquivos .tf
	terraform fmt -recursive

validate: ## Valida a configuração, sem AWS
	terraform init -backend=false -input=false >/dev/null
	terraform validate

plan: dono ## Mostra o que será alterado
	@test -f .terraform/terraform.tfstate || $(MAKE) --no-print-directory init
	terraform plan $(TF_VARS)

up: dono ## Sobe a plataforma (~15 min) e liga o ambiente nos pipelines. A cobrança começa aqui.
	@aws s3api head-bucket --bucket $(BUCKET) 2>/dev/null || { echo "Bucket do estado inexistente: rode 'make bootstrap'."; exit 1; }
	@test -f .terraform/terraform.tfstate || $(MAKE) --no-print-directory init
	terraform apply $(TF_VARS)
	@$(MAKE) --no-print-directory kubeconfig
	@./scripts/github.sh ligar || echo "⚠ AMBIENTE_ATIVO não foi ligado: rode 'make ambiente-ligar'."
	@echo "Plataforma no ar. Próximo passo: make github-segredos e os 'make infra-up' dos serviços."

down: dono ## Desliga o ambiente nos pipelines e destrói a plataforma
	@vivos="$$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'tech-challenge-f4')].FunctionName" --output text) $$(aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier, 'tech-challenge-f4')].DBInstanceIdentifier" --output text)"; \
		[ -z "$$(echo $$vivos | tr -d ' ')" ] || { echo "Ainda existem Lambda ou bancos dos serviços ($$vivos): destrua os outros repositórios antes."; exit 1; }
	@test -f .terraform/terraform.tfstate || $(MAKE) --no-print-directory init
	@if terraform state list 2>/dev/null | grep -q '^newrelic_' && [ -z "$$TF_VAR_newrelic_api_key" ] && ! grep -qE '^newrelic_api_key *= *"NRAK' terraform.tfvars 2>/dev/null; then \
		echo "Dashboard e alertas existem no New Relic: exporte NEW_RELIC_API_KEY e NEW_RELIC_ACCOUNT_ID antes do down."; exit 1; fi
	@./scripts/github.sh desligar || echo "⚠ AMBIENTE_ATIVO não foi desligado: rode 'make ambiente-desligar'."
	@# Interfaces órfãs do plugin de rede do EKS impedem a remoção das subnets: limpa e repete uma vez.
	terraform destroy $(TF_VARS) || { $(MAKE) --no-print-directory limpar-orfas && terraform destroy $(TF_VARS); }
	@$(MAKE) --no-print-directory limpar-orfas

limpar-orfas:
	@for eni in $$(aws ec2 describe-network-interfaces --filters Name=tag:cluster.k8s.amazonaws.com/name,Values=$(CLUSTER) Name=status,Values=available --query 'NetworkInterfaces[].NetworkInterfaceId' --output text); do \
		aws ec2 delete-network-interface --network-interface-id $$eni && echo "Interface órfã do cluster apagada: $$eni"; done
	@for sg in $$(aws ec2 describe-security-groups --filters Name=group-name,Values='eks-cluster-sg-$(CLUSTER)-*' --query 'SecurityGroups[].GroupId' --output text); do \
		aws ec2 delete-security-group --group-id $$sg && echo "Security group do cluster apagado: $$sg"; done

apply: up ## Sinônimo de up
destroy: down ## Sinônimo de down

github-segredos: conta ## Grava as credenciais AWS (OIDC ou sessão do laboratório) e as chaves do New Relic nos 5 repositórios
	@./scripts/github.sh segredos

ambiente-ligar: ## Liga AMBIENTE_ATIVO nos 5 repositórios
	@./scripts/github.sh ligar

ambiente-desligar: ## Desliga AMBIENTE_ATIVO nos 5 repositórios
	@./scripts/github.sh desligar

ambiente-status: ## Mostra AMBIENTE_ATIVO em cada repositório
	@./scripts/github.sh status

kubeconfig: conta ## Aponta o kubectl para o cluster
	aws eks update-kubeconfig --name $(CLUSTER) --region $(AWS_REGION)

output: ## Exibe os outputs
	terraform output

status: ## Estado do cluster e do RabbitMQ
	@kubectl get nodes -o wide 2>/dev/null || echo "cluster inacessível: rode 'make kubeconfig'"
	@kubectl get pods,svc -n mensageria 2>/dev/null || echo "namespace mensageria ainda não existe"

rabbitmq: ## Abre o painel do RabbitMQ em http://localhost:15672
	kubectl -n mensageria port-forward svc/rabbitmq 15672:15672

custo: ## O que pesa enquanto o cluster está de pé
	@echo "EKS control plane  US\$$ 0,100/h (suporte padrão; no estendido, US\$$ 0,60)"
	@echo "3x t3.medium       US\$$ 0,125/h (On-Demand)"
	@echo "NLB interno        US\$$ 0,023/h"
	@echo "EBS dos nodes      US\$$ 0,008/h"
	@echo "Total ligado       ~US\$$ 0,26/h, fora os RDS dos serviços"

local-up: ## Sobe RabbitMQ e os bancos da Saga localmente (docker compose)
	docker compose -f local/docker-compose.yml up -d --wait
	@echo "RabbitMQ: amqp://oficina:oficina@localhost:5672 · painel http://localhost:15672"
	@echo "PostgreSQL OS: localhost:5433 · Execução: localhost:5434 · MongoDB: localhost:27017 (rs0)"

local-down: ## Derruba o ambiente local e apaga os volumes
	docker compose -f local/docker-compose.yml down -v

local-status: ## Estado dos containers locais
	docker compose -f local/docker-compose.yml ps
