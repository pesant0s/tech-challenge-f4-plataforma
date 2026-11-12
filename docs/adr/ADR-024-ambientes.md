# ADR-024 · Desenvolvimento local com docker compose, entrega na AWS

| | |
|---|---|
| **Status** | Aceita |
| **Data** | 2026-11-12 |

## Contexto

O projeto não tem orçamento. A orientação do professor é que o LocalStack pode ser usado para
desenvolver e testar, mas a entrega precisa rodar em nuvem, com as automações e o CI/CD completos.
O EKS cobra por hora mesmo ocioso.

## Decisão

| Ambiente | Para quê | Como |
|---|---|---|
| Local | Desenvolvimento, testes e falhas provocadas | docker compose com os três serviços, dois PostgreSQL, MongoDB e RabbitMQ; LocalStack para a Lambda |
| CI | Build, testes, cobertura, qualidade e prova da imagem | GitHub Actions; o deploy só roda com `AMBIENTE_ATIVO=true` (ADR-013) |
| AWS | Ensaio e gravação | Base da Fase 03 (EKS, NLB, API Gateway, RDS), ligada por `make up` e destruída por `make down` |

Não há Kubernetes local: os manifestos são validados no CI (kubeconform) e exercitados no EKS.

## Motivo

- Tudo o que pode ser provado sem nuvem é provado sem custo.
- Um cluster local (kind) duplicaria a configuração de exposição e de observabilidade sem provar nada
  que o ensaio na AWS não prove, dentro de um prazo curto.
- O padrão `AMBIENTE_ATIVO` da Fase 03 já impede que um merge tente implantar com o ambiente desligado.

## Consequências

- Diferenças entre o docker compose e o EKS (rede, segredos, limites de memória) só aparecem no ensaio.
  Por isso os limites dos containers no compose são os mesmos dos manifestos.
- Uma conta AWS de laboratório da faculdade pode substituir a conta própria. Ela costuma ter
  credenciais temporárias e uma role pronta (`LabRole`) no lugar de roles próprias e OIDC, o que muda a
  autenticação do CI.
