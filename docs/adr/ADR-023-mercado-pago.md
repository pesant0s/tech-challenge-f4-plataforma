# ADR-023 · Cobrança pelo Mercado Pago com QR Code dinâmico, atrás de uma porta

| | |
|---|---|
| **Status** | Aceita |
| **Data** | 2026-11-12 |

## Contexto

O enunciado exige integração com o Mercado Pago e aponta para o QR Code dinâmico. O pagamento é
confirmado de forma assíncrona: o cliente lê o QR no app e paga quando quiser, até o QR expirar. O
ambiente é efêmero e precisa ser reproduzível por quem não tem conta no Mercado Pago.

## Decisão

- **Porta `ProvedorPagamento`** no Billing, com dois adapters escolhidos por `PAGAMENTO_PROVEDOR`:
  - `mercadopago`: Orders API (`POST /v1/orders` com `type: qr` e `mode: dynamic`, `X-Idempotency-Key`
    igual ao id do pagamento, `external_reference` igual ao id da OS), consulta por
    `GET /v1/orders/{id}`, cancelamento e reembolso. Credenciais de teste (sandbox).
  - `simulado`: gera um QR fictício e permite aprovar, recusar ou deixar expirar por rota de teste.
    É o padrão, para quem reproduz o projeto sem conta no Mercado Pago, e é o usado nos testes.
- **Confirmação por dois caminhos**, ambos idempotentes:
  - consulta periódica das cobranças pendentes, que funciona sem URL pública;
  - webhook `POST /billing/webhooks/mercadopago`, com a assinatura `x-signature` validada, que acelera
    a confirmação quando o ambiente tem URL pública.
- **Momento da cobrança**: depois da aprovação do orçamento e antes da execução. A falha na execução
  gera reembolso como compensação (ADR-018).
- A loja e o caixa exigidos pelo QR são criados uma vez por script.

## Motivo

- A porta mantém domínio e casos de uso iguais para os dois provedores, e os testes não dependem de rede.
- A consulta periódica resolve o webhook com URL que muda a cada subida do ambiente; o webhook reduz a
  espera durante a demonstração.
- Cobrar antes da execução dá à Saga uma compensação real com o provedor (reembolso).

## Consequências

- A documentação do Mercado Pago diverge no método e no caminho de cancelamento e reembolso. O adapter
  é validado no sandbox antes de ser dado como pronto.
- O QR expira (15 minutos por padrão). A expiração vira `PagamentoRecusado` com motivo
  `PAGAMENTO_EXPIRADO` e dispara a compensação.
- O access token e a chave do webhook são segredos do Billing. Sem eles, o serviço sobe com o adapter
  simulado.
