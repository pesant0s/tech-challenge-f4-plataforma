# ADR-020 · Um banco por serviço: PostgreSQL na OS e na Execução, MongoDB no Billing

| | |
|---|---|
| **Status** | Aceita |
| **Data** | 2026-11-12 |

## Contexto

Cada microsserviço precisa de banco próprio, com pelo menos um relacional e um não relacional na
solução. Nenhum serviço pode acessar o banco de outro.

## Decisão

| Serviço | Banco | Na nuvem | Localmente |
|---|---|---|---|
| OS Service | PostgreSQL | RDS próprio, criado pelo repositório do serviço | container no docker compose |
| Execução e Produção | PostgreSQL | RDS próprio, criado pelo repositório do serviço | container no docker compose |
| Billing | MongoDB | StatefulSet no cluster, replica set de 1 nó | container, replica set de 1 nó |

Cada serviço tem as próprias credenciais e o próprio segredo. Nenhum segredo de banco é compartilhado.

## Motivo

- **OS em PostgreSQL**: cliente, veículo, OS, histórico de status e estado da Saga são relacionais, e a
  transição de status precisa de trava de linha. É o banco da Fase 03, com as migrations prontas.
- **Execução em PostgreSQL**: a reserva de estoque já usa `SELECT ... FOR UPDATE`, e a fila de execução
  usa `FOR UPDATE SKIP LOCKED`, que o PostgreSQL oferece pronto.
- **Billing em MongoDB**: orçamento e pagamento são documentos fechados por OS, com os itens e as
  tentativas de cobrança embutidos. A atualização condicional (`updateOne` com filtro de estado) dá a
  idempotência das notificações do Mercado Pago sem tabela auxiliar.
- **MongoDB no cluster, e não DocumentDB**: o DocumentDB não tem free tier e cobra por hora; o MongoDB
  no cluster usa a mesma imagem do docker compose.

## Consequências

- Transações multi-documento no MongoDB exigem replica set, mesmo com um nó só. Todos os ambientes
  sobem o MongoDB assim.
- O MongoDB some a cada `make down`, como o RabbitMQ. O PostgreSQL fica no RDS, com snapshot final
  opcional, como na Fase 03.
- Dois RDS somam cerca de US$ 0,03/h ao ambiente ligado.
