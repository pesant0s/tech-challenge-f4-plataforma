# ADR-019 · Mensageria com RabbitMQ, dentro do cluster

| | |
|---|---|
| **Status** | Aceita — substitui a parte de mensageria do ADR-015 |
| **Data** | 2026-11-12 |

## Contexto

O ADR-015 (Fase 03) descartou mensageria porque não havia consumidor assíncrono. A Saga (ADR-018) cria
esse consumidor: os passos levam de segundos (reserva) a horas (aprovação do cliente), e um serviço
fora do ar não pode travar os outros. O enunciado pede mensageria (RabbitMQ, Kafka, SQS etc.).

## Decisão

RabbitMQ, implantado no próprio cluster e no docker compose, com duas exchanges topic:
`oficina.comandos` (orquestrador → participantes) e `oficina.eventos` (participantes → orquestrador),
uma quorum queue por consumidor com `x-delivery-limit` e DLQ na exchange `oficina.dlx`. A topologia
completa está em [`docs/contratos`](../contratos/README.md).

REST síncrono continua para o que é pergunta e resposta: as rotas públicas pelo API Gateway e a
consulta da Lambda de CPF ao OS Service (ADR-022).

## Alternativas

| Opção | Por que não |
|---|---|
| Amazon SQS + SNS | Bom na AWS, mas localmente exigiria emulador (LocalStack) e o código ficaria preso ao provedor |
| Amazon MQ (RabbitMQ gerenciado) | Cobra por hora, mesmo parado |
| Kafka ou MSK | Log distribuído é mais do que a Saga precisa; operação e custo maiores |

## Motivo

- O mesmo broker roda igual no docker compose e no EKS, sem emulador.
- Exchange topic com chave `<serviço>.<mensagem>` deixa cada serviço declarar só as filas que consome.
- Quorum queue com limite de entregas leva a mensagem envenenada para a DLQ sem laço infinito.
- O painel de gestão mostra filas, taxas e DLQ, o que ajuda a demonstrar a Saga.

## Consequências

- O RabbitMQ é estado dentro do cluster: some a cada `make down`. Isso é aceitável porque o ambiente é
  efêmero, e o outbox (ADR-021) republica o que ainda não foi confirmado.
- O cluster ganha um pod com volume persistente. A capacidade dos nodes precisa ser medida antes da
  gravação.
