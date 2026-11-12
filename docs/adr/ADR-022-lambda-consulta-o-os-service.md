# ADR-022 · A Lambda de CPF consulta o OS Service, e não o banco dele

| | |
|---|---|
| **Status** | Aceita — substitui o acesso direto ao banco da Fase 03 |
| **Data** | 2026-11-12 |

## Contexto

Na Fase 03 a Lambda de autenticação lia a tabela `clientes` do RDS da aplicação com pg8000 (ADR-009).
Na Fase 04 os clientes pertencem ao OS Service (ADR-017), e o enunciado proíbe um serviço de acessar o
banco de outro.

## Decisão

O OS Service expõe `POST /interno/clientes/autenticar`, que recebe o CPF/CNPJ normalizado e responde
com o cliente e se ele está ativo. A rota não passa pelo API Gateway: a Lambda, na VPC, chama o NLB
interno. A Lambda continua validando o CPF e emitindo o JWT.

## Motivo

- Cumpre a regra do enunciado sem mudar o contrato do token (claim `tipo`, `sub` = id do cliente).
- A regra de cliente ativo ou inativo fica só no OS Service.
- A Lambda perde o pg8000, o segredo do banco e o security group `cliente-db`.

## Consequências

- A autenticação passa a depender do OS Service estar no ar. Se ele não responder, a Lambda devolve 503,
  como fazia quando o banco caía.
- A rota interna não é exposta ao público; fora do cluster ela só é alcançável pela VPC.
