# ADR-018 · Saga orquestrada, com o orquestrador no OS Service

| | |
|---|---|
| **Status** | Aceita |
| **Data** | 2026-11-12 |

## Contexto

Abrir uma OS passa por três serviços: reservar peças (Execução), orçar e cobrar (Billing), enfileirar
para execução (Execução). Cada passo grava no banco do seu serviço, então não existe uma transação
única. Se um passo falhar, os anteriores precisam ser desfeitos. O enunciado aceita Saga orquestrada ou
coreografada e pede a escolha justificada.

## Decisão

Saga **orquestrada**. A classe `SagaAberturaOS`, no OS Service, guarda o estado de cada Saga na tabela
`saga_instancia` (passo atual, prazo, motivo da falha). Ela envia comandos à Execução e ao Billing pela
exchange `oficina.comandos` e reage aos eventos que eles publicam em `oficina.eventos`. Os passos, os
eventos e as compensações estão em [`docs/contratos`](../contratos/README.md).

## Alternativas

| Critério | Orquestrada | Coreografada |
|---|---|---|
| Onde está a regra do fluxo | Numa classe, num serviço | Espalhada pelos três serviços |
| Compensação | Explícita, na ordem inversa, disparada pelo orquestrador | Cada serviço escuta as falhas dos outros e decide sozinho |
| Estado da Saga | Uma linha consultável em `saga_instancia` | Reconstruído a partir dos eventos |
| Prazo de um passo | Varredura de `saga_instancia.expira_em` | Cada participante precisa de um temporizador próprio |
| Teste do fluxo completo | BDD num repositório, com participantes simulados | Exige subir os três serviços |
| Acoplamento | O orquestrador conhece todos os passos | Nenhum serviço conhece o fluxo inteiro |

## Motivo

- O fluxo é linear e tem um dono natural: a OS. Quem precisa saber em que passo ela está é o OS Service.
- A compensação mais delicada, reembolsar quando a execução não pode começar, depende de saber que o
  pagamento foi confirmado. Na orquestração essa informação está numa linha; na coreografia, o Billing
  teria que escutar eventos da Execução e decidir por conta própria.
- Com três serviços, o custo da orquestração (um ponto que conhece o fluxo) é pequeno, e o ganho em
  clareza, teste e demonstração é grande.

## Consequências

- O OS Service concentra o conhecimento do fluxo. Um passo novo muda o orquestrador e o participante.
- Execução e Billing não se conhecem; só respondem a comandos.
- Toda compensação precisa ser idempotente, porque o orquestrador pode repeti-la depois de uma falha.
- A Saga pode parar em `FALHA_NA_COMPENSACAO` (reembolso recusado pelo provedor). Esse estado gera
  alerta e exige ação humana.
