---
name: models-secao3
description: Decisoes de implementacao dos 11 models + 2 concerns da Secao 3 (348 testes passando)
metadata:
  type: project
---

Secao 3 concluida em 2026-05-25. 11 models + 2 concerns implementados. 348 testes, 610 assertions, 0 failures, 0 errors.

**Why:** Implementacao dos models base do dominio (Users, Voices, Orders, Briefings, etc.) seguindo plano aprovado pelo task-planner.

**How to apply:** Ao continuar o projeto, estes models estao prontos e testados. Nao modificar sem rodar testes.

## Decisoes fechadas

1. **AASM NAO entra** — Order usa `status` como string com inclusion validation via Statusable
2. **User Devise modules:** `:database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :confirmable, :lockable, :timeoutable, :trackable`
3. **confirmation_required? override:** retorna `false` se `guest?`, retorna `true` (hard) para nao-guests (NAO delega para super — super retorna false quando confirmed_at presente)
4. **Voice:** validacao custom `external_id OR mureka_prompt` via `validate :external_id_or_mureka_prompt_present`
5. **Enums substituidos por constantes:** `STATUSES`, `PROVIDERS`, etc. + `inclusion: { in: CONSTANT }`. Rails `enum` nao usado.
6. **EmailDelivery NAO inclui Brandable** — so validacao inline de brand (BRANDS constante)
7. **Statusable concern:** `validates :status, inclusion: { in: self::STATUSES }` no `included do` block
8. **Voice#for_tier(integer):** scope recebe integer direto. Conversao "pro"->1 fica no caller.
9. **Order#locale_valid_for_brand:** skip validacao se brand invalido (nao esta em BRANDS)
10. **Voice -> music_generations:** `dependent: :restrict_with_error`
11. **LyricsDraft -> music_generations:** `dependent: :restrict_with_error`

## Brandable concern

Metodos `b2b?` e `b2c?` delegam para `brand_value` (cada model implementa como private method).
User: `brand_value = origin_brand`
Order: `brand_value = brand`
EmailDelivery NAO inclui Brandable por decisao de design (decisao #6).

## Scopes

- `LyricsDraft.latest_for(order_id)` retorna objeto unico (`.first`), NAO relacao
- `Voice.for_brand(brand_str)` usa query PG array: `where("? = ANY(allowed_brands)", brand_str)`
- `Voice.for_tier(tier_int)` usa: `where("min_tier <= ?", tier_int)`

## StripeEvent

`alias already_processed? processed?` — metodo alias simples.

## EmailDelivery#delivered?

Retorna true quando status in `%w[sent opened clicked]`.

## Fixtures

11 fixtures com label-based FK. Fixtures de voices usam formato PG array: `allowed_brands: "{b2b,b2c}"`.
