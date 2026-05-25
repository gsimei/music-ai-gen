---
name: aasm-secao4
description: AASM state machine na Order — decisoes de design, callbacks, guards, gems instaladas, 393 testes passando
metadata:
  type: project
---

Seção 4 concluída: AASM state machine implementada na Order com 393 testes passando.

**Why:** Fluxo central da plataforma — 14 estados cobrem o ciclo completo do pedido, do briefing ao download.

**How to apply:** Ao tocar em Order.status ou em qualquer transição, verificar a state machine antes de propor mudanças. Callbacks são after_commit (jobs) ou after (locks síncronos).

## Gem instalada
- `after_commit_everywhere 1.6.0` — necessária para callbacks after_commit fora de bloco de transação ActiveRecord

## Decisões fechadas

1. **cancel events from:** `pending, payment_failed, paid, lyrics_drafting, lyrics_ready, lyrics_failed, music_failed` (7 estados elegíveis)
2. **cancel + refund são 2 eventos separados** — refund: cancelled → refunded
3. **approve_lyrics** usa `attr_accessor :current_lyrics_draft_id` (virtual, não argumento AASM)
4. **lock_lyrics_and_start_music** é método privado no model (refatora para service na Seção 10)
5. `aasm column: :status, requires_new_transaction: false`

## Arquivos criados/modificados
- `app/models/order.rb` — removeu `include Statusable`, removeu scopes `paid`/`delivered` (AASM gera), adicionou AASM block completo
- `app/jobs/generate_lyrics_job.rb` — stub, queue :ai
- `app/jobs/deliver_order_job.rb` — stub, queue :default
- `app/mailers/order_mailer.rb` — 3 actions: lyrics_ready, preview_ready, delivered
- `app/views/order_mailer/` — 6 views ERB stub (html + text para cada action)
- `test/models/order_test.rb` — nova classe OrderAasmTest (Groups A–F)
- `test/fixtures/orders.yml` — 7 novos fixtures de estados intermediários
- `test/fixtures/lyrics_drafts.yml` — fixture `draft_lyrics_ready_v1` para testes do guard
- `test/test_helper.rb` — adicionado `ActionMailer::Base.delivery_method = :test`

## Scopes AASM gerados automaticamente
AASM gera scopes com nome igual ao estado. Scopes manuais `paid` e `delivered` foram removidos — conflitariam. Mantidos: `for_brand`, `recent`, `pending_payment`.

## Padrão de teste AASM
- Classe separada `OrderAasmTest < ActiveSupport::TestCase` com `include ActiveJob::TestHelper` e `include ActionMailer::TestHelper`
- `assert_enqueued_with` para jobs, `assert_emails` para mailers
- `perform_enqueued_jobs` nos testes de transições com after_commit que dispara jobs (evita que job enfileirado seja contado no assert mas não executado)

## Estado do suite
393 testes, 709 assertions, 0 failures, 0 errors — em 2026-05-25
