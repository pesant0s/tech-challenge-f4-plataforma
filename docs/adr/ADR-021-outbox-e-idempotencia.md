# ADR-021 · Outbox transacional na publicação e consumo idempotente

| | |
|---|---|
| **Status** | Aceita |
| **Data** | 2026-11-12 |

## Contexto

Cada passo da Saga grava no banco e publica uma mensagem. Se o serviço cair entre o commit e a
publicação, a Saga fica parada para sempre; se publicar antes do commit e o commit falhar, os outros
serviços agem sobre algo que não aconteceu. Do outro lado, o RabbitMQ entrega "pelo menos uma vez":
o mesmo comando pode chegar duas vezes.

## Decisão

- **Outbox**: a mensagem é gravada numa tabela `outbox` (PostgreSQL) ou coleção `outbox` (MongoDB) na
  mesma transação da mudança de estado. Um relay, no mesmo processo, lê o que não foi publicado,
  publica com *publisher confirms* e só então marca como publicado.
- **Inbox**: o consumidor grava o `message_id` em `mensagens_processadas` na mesma transação do efeito.
  Se o `message_id` já existe, ele confirma (`ack`) sem repetir o efeito.
- **ack manual**, enviado só depois do commit. Erro inesperado → `nack` com reentrega; na sexta entrega
  a mensagem vai para a DLQ (ADR-019).

## Alternativas

| Opção | Por que não |
|---|---|
| Publicar direto depois do commit | Perde a mensagem se o processo cair entre os dois |
| Transação distribuída (2PC) | O RabbitMQ não participa de XA, e o MongoDB não fala com o PostgreSQL |
| Change Data Capture (Debezium) | Mais um componente para operar, sem ganho num projeto deste tamanho |

## Consequências

- A entrega passa a ser "pelo menos uma vez" de ponta a ponta, e a idempotência do consumidor torna o
  efeito "exatamente uma vez".
- O relay pode publicar uma mensagem duas vezes (cai depois de publicar e antes de marcar). A inbox do
  consumidor absorve isso.
- O outbox também resolve o broker efêmero: se o RabbitMQ for recriado, o que não foi confirmado é
  publicado de novo.
