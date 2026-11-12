# ADR-017 · Três microsserviços, divididos pelas áreas da oficina

| | |
|---|---|
| **Status** | Aceita |
| **Data** | 2026-11-12 |

## Contexto

A Fase 04 exige ao menos três microsserviços independentes, cada um com repositório, infraestrutura e
banco próprios, e proíbe um serviço de acessar o banco de outro. A aplicação da Fase 03 é um monólito
hexagonal com cinco módulos: atendimento (OS), cadastro, autenticação, catálogo e estoque.

## Decisão

| Serviço | Responsabilidade | Módulos da Fase 03 que absorve |
|---|---|---|
| **OS Service** | Abertura, status e histórico da OS; clientes, veículos, usuários e login; orquestra a Saga (ADR-018) | atendimento, cadastro, autenticação |
| **Execução e Produção** | Catálogo de serviços e peças, estoque (reserva, baixa e liberação), fila de execução, diagnóstico e reparo | catálogo, estoque, fila de OS |
| **Billing** | Orçamento, aprovação pelo cliente, cobrança e reembolso no Mercado Pago | aprovação e rejeição da OS, webhook de resposta do cliente |

Os repositórios seguem o prefixo `tech-challenge-f4-`: `os-service`, `execucao-service`,
`billing-service`, `auth-lambda` e `plataforma`. Os três serviços nasceram como bifurcação do
`tech-challenge-app`, preservando o histórico, e cada um remove o que não lhe pertence.

## Motivo

- São as três áreas que o desafio cita (atendimento, execução, cobrança) e os três exemplos do enunciado.
- Cada serviço é dono de um conjunto de dados que só ele altera: a OS e quem a pediu, o que há em
  estoque e na fila, e o que foi cobrado.
- Cadastro e autenticação ficam com a OS porque toda OS nasce de um cliente e de um veículo. Separá-los
  num quarto serviço criaria uma chamada síncrona em toda abertura de OS, sem ganho para o desafio.
- Catálogo e estoque ficam com a Execução porque a reserva de peças precisa do preço e da quantidade
  na mesma transação.

## Consequências

- O preço dos itens passa a vir da Execução, na resposta da reserva (`PecasReservadas`). O OS Service
  não conhece mais catálogo nem estoque.
- A aprovação do orçamento sai do OS Service e vai para o Billing; o OS Service só recebe o resultado.
- A Lambda de CPF não pode mais ler a tabela `clientes` (ADR-022).
