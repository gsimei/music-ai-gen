---
name: wizard-briefing-secao7
description: Wizard de briefing (Secao 7): services, controller, rotas e views implementados, 515 testes passando
metadata:
  type: project
---

## Arquivos implementados

- `app/services/orders/reference_generator.rb` — module com `generate!(year:)`, loop de unicidade, max 100 tentativas
- `app/services/orders/wizard_session.rb` — plain Ruby wrapper de `session[:order_wizard]`, sentinels por step, `step_accessible?`, `clear!`
- `app/services/orders/step_validator.rb` — `ActiveModel::Model`, valida campos do step indicado, `attr_accessor` para todos os campos de erro
- `app/services/orders/create_draft_service.rb` — herda BaseService, cria Order + Briefing em transaction
- `app/controllers/orders_controller.rb` — `new`, `show`, `wizard_show`, `wizard_update`, sem `authenticate_user!`
- `app/policies/order_policy.rb` — stub com `show?`
- `app/views/orders/wizard/step_1..5.html.erb` — stubs funcionais
- `app/views/orders/show.html.erb` — stub

## Decisoes criticas

### ActiveModel::Errors exige attr_accessor nos campos de erro
Qualquer classe com `ActiveModel::Model` que usa `errors.add(:field, ...)` precisa declarar `attr_accessor :field`.
Sem isso: `NoMethodError: undefined method 'field'` ao acessar `errors[:field]`.
Aplica-se ao StepValidator E ao CreateDraftService.

**Why:** ActiveModel::Errors internamente tenta chamar o metodo do atributo no modelo quando o errors object e inspecionado.

### Fluxo de validacao no service nao usa &&
No `CreateDraftService#call`, os tres metodos de validacao (`validate_required_fields!`, `validate_tier!`, `validate_voice!`) sao chamados sequencialmente sem `&&`. Usar `&&` faz curto-circuito quando o primeiro retorna nil (o que acontece sempre com `.each`), silenciando validacoes subsequentes.

**How to apply:** Sempre chamar metodos de validacao linha a linha; verificar `errors.any?` depois de todos.

### Rotas com duplo BrandConstraint — as: apenas no primeiro bloco
`wizard_order_path` e `new_order_path` definidos com `as:` no bloco b2b, omitido no bloco b2c para evitar conflito de nome. Rails usa a ultima definicao de rota para resolucao de URL; ambas apontam para o mesmo controller.

### WizardSession — step 3 usa sentinel `step_3_visited`
Step 3 nao tem campo obrigatorio, entao usa um sentinel booleano para marcar que foi visitado. `update!` aceita `step:` keyword para injetar o sentinel automaticamente.

### Tier → min_tier mapeamento
- `standard` (b2c) → 0
- `starter` (b2b) → 0
- `pro` (qualquer brand) → 1
Definido em `TIER_MIN_TIER_MAP` no service. Nao hardcodar em outro lugar.

### guest_order? no Order model
`user.nil? || user.guest?` — orders sem user_id sao validos (guest checkout).

## Contagem de testes
515 testes, 958 assertions, 0 failures, 0 errors — incluindo 84 novos da Secao 7.
