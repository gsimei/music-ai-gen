# Roadmap — Music AI Gen

Cronograma de implementação baseado no SPEC.md (seção 19). Marcar tarefas conforme forem concluídas.

**Legenda:** `[ ]` pendente · `[~]` em progresso · `[x]` concluído

**Design de referência:** `Plataforma - Vanilla.html` (raiz do projeto) — protótipo HTML/JS vanilla com B2B e B2C. Toda task de frontend deve consultar antes de implementar (ver CLAUDE.md).

---

## 1. Setup base

- [x] Adicionar gems ao Gemfile (devise, pundit, aasm, stripe, anthropic, sentry-rails, webmock, dotenv-rails)
- [x] `bundle install`
- [x] Configurar Solid Queue (filas nomeadas: default, critical, mailers, ai)
- [x] Configurar Sentry (initializer + DSN via ENV)
- [x] Configurar Devise (gerador + User model base)
- [x] Configurar Pundit (application_policy + ApplicationController)
- [x] Criar `BaseService` em `app/services/base_service.rb` + `ServiceResult`
- [x] Configurar `config/brands.yml` com tiers e hosts
- [x] Setup de variáveis de ambiente (`.env.example` commitado, `.env` local ignorado)

## 2. Schema do banco de dados

- [x] Migration 1: `users` (Devise + campos de negócio)
  - Incluir módulos Devise: `:lockable`, `:confirmable`, `:trackable`, `:timeoutable` (security review C-1/A-1/A-2)
  - Habilitar `config.paranoid = true` em `devise.rb` (A-3 — anti enumeration)
  - Configurar `lock_strategy`, `maximum_attempts: 10`, `unlock_in: 1.hour`, `timeout_in: 30.minutes`
  - Configurar `sign_in_after_reset_password = false` (M-5)
- [x] Migration 2: `voices` (catálogo Mureka — inclui `mureka_prompt`, `external_id` nullable)
- [x] Migration 3: `orders`
- [x] Migration 4: `briefings`
- [x] Migration 5: `lyrics_drafts`
- [x] Migration 6: `music_generations`
- [x] Migration 7: `generation_jobs` (log LLM)
- [x] Migration 8: `order_assets`
- [x] Migration 9: `stripe_events` (idempotência webhook)
- [x] Migration 10: `refund_requests`
- [x] Migration 11: `email_deliveries`
- [x] `db:migrate` + verificar `schema.rb`

## 3. Models, associations e validations

- [x] `User` (sem AASM)
- [x] `Voice`
- [x] `Order` (sem AASM ainda)
- [x] `Briefing`
- [x] `LyricsDraft`
- [x] `MusicGeneration`
- [x] `GenerationJob`
- [x] `OrderAsset`
- [x] `StripeEvent`
- [x] `RefundRequest`
- [x] `EmailDelivery`

## 4. State machine (AASM) na Order

- [ ] Instalar gem + setup
- [ ] Definir todos os 13 estados
- [ ] Implementar todas as transições + guards
- [ ] Callbacks `after` (jobs e mailers)
- [ ] Testes de todas as transições válidas e inválidas

## 5. Brand/Locale resolver

- [ ] Service `BrandLocaleResolver` (detecta brand+locale por host)
- [ ] `before_action` no `ApplicationController` setando `@brand` e `I18n.locale`
- [ ] Routes com `constraints` por host
- [ ] Helper `t_brand(key)` em `ApplicationHelper`
- [ ] Setup multi-host em `development` (hosts file ou similar)

## 6. Seed do catálogo de vozes

- [ ] `db/seeds/voices.rb` com vozes placeholder
- [ ] `db/seeds.rb` chamando o arquivo de vozes

## 7. Wizard de briefing

- [ ] `OrdersController#new` com Turbo Frames multi-step
- [ ] Step 1: dados básicos (about, recipient, occasion)
- [ ] Step 2: estilo musical (music_style, mood, tempo, duration)
- [ ] Step 3: keywords e avoid
- [ ] Step 4: escolha de voz (filtrada por brand/tier)
- [ ] Step 5: revisão + escolha de tier
- [ ] Persistência de rascunho entre steps
- [ ] Validações por step

## 8. Stripe Checkout + webhook

- [ ] Service `Stripe::CheckoutBuilder` (cria Checkout Session)
- [ ] Endpoint `POST /orders/:id/checkout`
- [ ] Endpoint `POST /stripe/webhook` (verificação HMAC)
- [ ] Service `Stripe::WebhookHandler` (idempotência via StripeEvent)
- [ ] Job `StripeWebhookProcessorJob`
- [ ] Handlers: `checkout.session.completed`, `payment_intent.payment_failed`, `charge.refunded`
- [ ] Testes com WebMock

## 9. LyricsGenerator — pipeline dupla (Mureka → Claude)

- [ ] **DECISÃO PENDENTE**: confirmar se `POST /v1/lyrics/generate` da Mureka desconta créditos (ver SPEC 13.1)
- [ ] Service `LyricsGenerator::MurekaLyricsClient` (etapa 1 — rascunho bruto) — só se Mureka for inclusa
- [ ] Service `LyricsGenerator::ClaudeClient` (wrapper Anthropic API — etapa 2 refino + regen)
- [ ] Service `LyricsGenerator::PromptBuilder` (REFINE_PROMPT, REGEN_PROMPT, ou direct se sem Mureka)
- [ ] Service `LyricsGenerator::Generator` (orquestra Mureka → Claude → save em lyrics_drafts)
- [ ] Job `GenerateLyricsJob` (suporta initial + regen)
- [ ] Versionamento de prompt (`prompt_version`)
- [ ] Log em `GenerationJob` (uma row por chamada Mureka + uma por chamada Claude)
- [ ] Testes com WebMock (Mureka + Anthropic)

## 10. Revisão de letra (UI simplificada — ver SPEC 10.1)

- [ ] View `/orders/:id/lyrics` — letra como texto corrido, sem blocos editáveis por seção
- [ ] Dois botões: "Está perfeita ✓" / "Quero ajustar"
- [ ] Campo de texto livre para feedback (quando "Quero ajustar")
- [ ] Contador discreto de regenerações restantes
- [ ] Stimulus controller mínimo (toggle do feedback form, submit via Turbo)
- [ ] Turbo Streams substituem a letra quando o job de regen termina
- [ ] Botão "Quero ajustar" desabilitado quando regen_limit atingido
- [ ] Endpoint `POST /orders/:id/approve_lyrics` (trava letra + dispara música)
- [ ] Endpoint `POST /orders/:id/lyrics/regenerate` (cria nova draft + enfileira job)
- [ ] **NÃO implementar:** blocos editáveis, regen por bloco, exposição da JSON structure

## 11. MurekaClient + integração

- [ ] Service `MusicGenerator::MurekaClient` (wrapper Mureka API)
- [ ] Service `MusicGenerator::Generator` (orquestra geração + polling)
- [ ] Job `GenerateMusicJob`
- [ ] Job `PollMurekaStatusJob` (se sem webhook)
- [ ] Endpoint `POST /webhooks/mureka` (se webhook disponível)
- [ ] Testes com WebMock

## 12. AudioProcessor (FFmpeg)

- [ ] Service `MusicGenerator::AudioProcessor` (FFmpeg via shell)
- [ ] Job `ProcessMusicPreviewJob` (corta 30s + fade-out + upload S3)
- [ ] Tratamento de erros do FFmpeg
- [ ] Testes (com fixture de áudio)

## 13. Preview / approval flow

- [ ] View `/orders/:id/preview` (player A/B)
- [ ] Stimulus controller do player (play/pause/switch)
- [ ] Endpoint `POST /orders/:id/approve_music` (escolhe variante)
- [ ] UI de feedback se regeneração necessária

## 14. Delivery flow

- [ ] Service `Delivery::AssetUploader` (baixa Mureka → S3/R2)
- [ ] Service `Delivery::SignedUrlGenerator` (URL assinada com expiração)
- [ ] Job `DeliverOrderJob`
- [ ] View `/orders/:id/download`
- [ ] Endpoint `GET /orders/:id/download/:asset_id` (valida ownership + signed URL)
- [ ] Tracking de downloads (`download_count`, `first_download_at`)

## 15. Email templates

- [ ] Setup ActionMailer + provider (Postmark ou Resend)
- [ ] Layouts por brand (`b2b/`, `b2c/`)
- [ ] Template `order_confirmation` (todos os locales)
- [ ] Template `lyrics_ready`
- [ ] Template `preview_ready`
- [ ] Template `order_delivered`
- [ ] Template `refund_processed`
- [ ] Template `order_failed`
- [ ] Registro em `EmailDelivery`

## 16. Admin panel

- [ ] Setup Administrate (ou montar manual com Pundit)
- [ ] `/admin/orders` (lista, filtros, detalhe)
- [ ] `/admin/voices` (CRUD)
- [ ] `/admin/refund_requests` (gestão de refunds)
- [ ] Policy Pundit para role `admin` / `support`

## 17. Landing pages

- [ ] Landing B2B (`/`)
- [ ] Landing B2C (`/`)
- [ ] `/pricing`
- [ ] `/exemplos` (galeria)
- [ ] `/faq`
- [ ] `/terms`
- [ ] `/privacy`

## 18. Testes — cobertura final

- [ ] Unit: todos os service objects
- [ ] Integration: jobs Solid Queue + webhook handlers
- [ ] System: fluxo completo (briefing → checkout fake → letra → música mockada → download)
- [ ] State machine: transições válidas e inválidas

---

## Pre-deploy security checklist

Itens da revisão de segurança (security-engineer, 2026-05-25) que devem ser endereçados antes do primeiro deploy em staging/produção. Não bloqueiam desenvolvimento local.

### Antes do primeiro deploy em staging

- [ ] **M-1**: Habilitar `config.force_ssl = true` e `config.assume_ssl = true` em `production.rb` (HSTS + Secure cookies via Kamal/Thruster TLS termination)
- [ ] **M-3**: Configurar `config.hosts` em `production.rb` com hosts B2B/B2C (DNS rebinding protection)
- [ ] **M-7**: Adicionar `before_send` no Sentry filtrando query strings (evitar vazar `confirmation_token`/`reset_password_token` em traces)
- [ ] **B-2**: Trocar `mailer_sender` e `default_url_options` placeholders por `ENV.fetch(...)` (evitar emails de `example.com` em staging)

### Antes do frontend ir para staging

- [ ] **M-2**: Habilitar Content Security Policy em `config/initializers/content_security_policy.rb` (com nonce para Tailwind/Stimulus)

### Antes da Seção 14 (Storage / R2)

- [ ] **M-4**: Trocar `config.active_storage.service = :local` para `:r2` em `production.rb`

### Após primeiros controllers autenticados

- [ ] **M-6**: Adicionar `after_action :verify_authorized` + `:verify_policy_scoped` no ApplicationController (com skip para Devise controllers)

### Hardening incremental (sem urgência)

- [ ] **B-1**: Ajustar valores placeholder de Stripe no `.env.example` (evitar confusão com chaves parciais)
- [ ] **B-4**: Usar `ENV["SENTRY_DSN"].presence` em vez de `ENV["SENTRY_DSN"]`
- [ ] **B-5**: Quando seções de pagamento e dados bancários existirem, adicionar `:card_number`, `:iban` ao `filter_parameter_logging`
- [ ] **B-6**: Criar `config/initializers/session_store.rb` explícito quando `force_ssl` estiver ativo

---

## Itens fora do MVP (não implementar agora)

- Voice cloning (GDPR/AI Act)
- Assinatura recorrente
- App nativo (Hotwire Native)
- SSO/OAuth
- Marketplace de músicas geradas
