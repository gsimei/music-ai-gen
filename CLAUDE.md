# Music AI Gen — Instruções para o Claude

Plataforma web de geração de músicas personalizadas com AI. Clientes preenchem um briefing, pagam via Stripe, revisam a letra gerada por LLM, aprovam e recebem duas variantes de música para escolher, e baixam o arquivo final.

Duas marcas independentes sob o mesmo backend:
- **B2B** (jingles para pequenos negócios) — ticket €79–149
- **B2C** (música como presente) — ticket €19–39

Mercado: Europa, com Itália como mercado principal. Multi-idioma (it, en, es, fr, de, pt).

---

## Stack

| Camada | Tecnologia |
|---|---|
| Linguagem | Ruby 3.x |
| Framework | Rails 8.1 |
| Banco de dados | PostgreSQL 16 |
| Frontend | Hotwire (Turbo + Stimulus), Tailwind CSS 4 |
| Auth | Devise + Pundit |
| Background jobs | Solid Queue |
| Pagamento | Stripe Checkout + webhooks |
| Storage | ActiveStorage + Cloudflare R2 |
| Email | Postmark ou Resend |
| Áudio | FFmpeg (server-side) |
| AI — Letras | Anthropic Claude (claude-opus-4-7) |
| AI — Música | Mureka API (platform.mureka.ai) |
| Deploy | Kamal 2 (Docker) |
| Monitoramento | Sentry |

---

## Comandos essenciais

```bash
bin/dev                          # inicia o servidor de desenvolvimento
bin/rails test                   # suite completa de testes
bin/rails test test/models/      # testes por categoria
bin/rails db:migrate             # roda migrations pendentes
kamal deploy                     # deploy de nova versão
```

---

## MCP Servers

Usado pelo agente `frontend-analyzer`. O servidor de desenvolvimento deve estar rodando (`bin/dev`) antes de acioná-lo.

```bash
# Instalar (primeira vez)
pnpm dlx playwright install chromium

# Registar os MCPs no Claude Code
claude mcp add playwright -- pnpm dlx @playwright/mcp@latest
claude mcp add filesystem -- pnpm dlx @modelcontextprotocol/server-filesystem $(pwd)
```

---

## Fluxo obrigatório de desenvolvimento (Agent Workflow)

**NUNCA escreva código de implementação sem seguir este fluxo:**

```
idea-validator → task-planner → tdd-architect → backend-architect if needed → frontend-architect if needed → minitest-runner → [security-engineer]
```

Para features de frontend, incluir análise visual antes do merge:

```
frontend-architect → frontend-analyzer → minitest-runner → [security-engineer]
```

### Etapas

**1. idea-validator** — SEMPRE o primeiro passo ao receber uma ideia nova, bug report vago ou proposta de refactor
- Lê SPEC.md e db/schema.rb para entender o contexto atual
- Discute a ideia com o usuário: problema, valor, edge cases, alternativas mais simples
- Só libera para o task-planner quando a ideia estiver bem definida
- **NÃO escreve código, NÃO produz planos técnicos**

**2. task-planner** — após validação da ideia, ANTES de qualquer implementação
- Lê SPEC.md e db/schema.rb
- Analisa o código existente e padrões do projeto
- Produz um plano detalhado de implementação
- Aguarda aprovação antes de prosseguir
- **NÃO escreve código**

**3. tdd-architect** — OBRIGATÓRIO após aprovação do plano, ANTES de qualquer implementação
- Recebe o plano aprovado
- Define a estratégia de testes (unit, integration, system)
- Escreve os testes que devem FALHAR (fase red do TDD)
- Aciona minitest-runner para confirmar falha correta
- **NÃO escreve código de implementação**

**4. backend-architect** ou **frontend-architect** — implementação
- **backend-architect**: modelos, services, controllers, jobs, APIs, migrações
- **frontend-architect**: ViewComponents, Tailwind, Stimulus, acessibilidade
- Implementa seguindo o plano e fazendo os testes passarem (fase green)

**5. minitest-runner** — após implementação
- Roda os testes e confirma que todos passam
- Diagnostica falhas se houver
- Se a mudança tocar auth, pagamentos, upload de arquivos ou multi-tenant → aciona security-engineer

**6. security-engineer** — quando aplicável
- Revisão de segurança antes do merge
- Obrigatório para: autenticação, autorização, dados sensíveis, integrações externas (Stripe, Mureka, Claude)

### Quando usar cada agent diretamente

| Situação | Agent |
|---|---|
| Ideia nova, bug vago ou proposta de refactor | `idea-validator` |
| Ideia validada, pronta para planejar | `task-planner` |
| Plano aprovado, antes de implementar | `tdd-architect` |
| Implementar backend (models, services, APIs) | `backend-architect` |
| Implementar frontend (UI, ViewComponent) | `frontend-architect` |
| Análise visual, acessibilidade, Turbo/Stimulus | `frontend-analyzer` |
| Rodar / debugar testes | `minitest-runner` |
| Revisão de segurança | `security-engineer` |
| Pesquisa técnica (APIs externas, regulações) | `research-scientist` |
| Documentação | `technical-writer` |

---

## Convenções do projeto

### Services (BaseService)
```ruby
class MyService < BaseService
  attribute :param, :string
  validates :param, presence: true

  def call
    return failure_result(errors) unless valid?
    # lógica
    success_result(value)
  end
end
```

### Multi-brand / Multi-locale
- Brand (`b2b` | `b2c`) detectada pelo host da requisição via `before_action`
- Locale detectado por host (`.it` → força `it`) ou `Accept-Language`
- `@brand` e `I18n.locale` disponíveis em todos os controllers
- Helper `t_brand(key)` resolve chaves por brand com fallback para chave global
- Preços e limites configurados em `config/brands.yml` — **nunca hardcoded**

### State machine (AASM)
- Order tem 9 estados funcionais + estados de falha (ver SPEC.md seção 8)
- Transições disparam side effects via callbacks `after`
- Nunca mudar `status` diretamente — sempre via eventos AASM

### Enums
- **NUNCA** usar `none` como valor de enum — conflita com `ActiveRecord::Base.none`
- Usar `no_adjustment`, `not_applicable`, etc.

### Jobs (Solid Queue)
- Retry: exponential backoff, máx 5 tentativas
- Após esgotar tentativas: status vai para `_failed`, admin notificado por email

### Stripe
- Webhook retorna 200 SEMPRE que a assinatura é válida — processamento é assíncrono
- Idempotência via tabela `stripe_events` (chave `stripe_event_id`)

### Storage
- Bucket público (previews 30s, samples, avatars): URLs diretas
- Bucket privado (MP3 completo, WAV, stems): signed URLs com expiração de 1h
- Cliente nunca recebe URL direta do bucket privado — sempre via `/orders/:id/download/:asset_id`

### Testes
- Framework: Minitest
- Services: testar `success_result` e `failure_result`
- Clients externos (Claude, Mureka, Stripe): usar WebMock
- Jobs: testar enfileiramento e execução
