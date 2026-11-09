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

- [x] Instalar gem + setup (after_commit_everywhere 1.6.0)
- [x] Definir todos os 14 estados
- [x] Implementar todas as transições + guards
- [x] Callbacks `after` (jobs e mailers)
- [x] Testes de todas as transições válidas e inválidas

## 5. Brand/Locale resolver

- [x] Service `BrandLocaleResolver` (detecta brand+locale por host)
- [x] `before_action` no `ApplicationController` setando `@brand` e `I18n.locale`
- [x] Routes com `constraints` por host
- [x] Helper `t_brand(key)` em `ApplicationHelper`
- [x] Setup multi-host em `development` (hosts file ou similar)

## 6. Seed do catálogo de vozes

- [x] `db/seeds/voices.rb` com vozes placeholder
- [x] `db/seeds.rb` chamando o arquivo de vozes

## 7. Wizard de briefing

- [x] `OrdersController#new` com Turbo Frames multi-step
- [x] Step 1: dados básicos (about, recipient, occasion)
- [x] Step 2: estilo musical (music_style, mood, tempo, duration)
- [x] Step 3: keywords e avoid
- [x] Step 4: escolha de voz (filtrada por brand/tier)
- [x] Step 5: revisão + escolha de tier
- [x] Persistência de rascunho entre steps
- [x] Validações por step

## 8. Stripe Checkout + webhook

- [x] Service `Stripe::CheckoutBuilder` (cria Checkout Session)
- [x] Endpoint `POST /orders/:id/checkout`
- [x] Endpoint `POST /stripe/webhook` (verificação HMAC)
- [x] Service `Stripe::WebhookHandler` (idempotência via StripeEvent)
- [x] Job `StripeWebhookProcessorJob`
- [x] Handlers: `checkout.session.completed`, `payment_intent.payment_failed`, `charge.refunded`
- [x] Testes com WebMock

## 9. LyricsGenerator — pipeline dupla (Mureka → Claude)

- [x] **DECISÃO PENDENTE**: confirmar se `POST /v1/lyrics/generate` da Mureka desconta créditos (ver SPEC 13.1)
- [x] Service `LyricsGenerator::MurekaLyricsClient` (etapa 1 — rascunho bruto) — só se Mureka for inclusa
- [x] Service `LyricsGenerator::ClaudeClient` (wrapper Anthropic API — etapa 2 refino + regen)
- [x] Service `LyricsGenerator::PromptBuilder` (REFINE_PROMPT, REGEN_PROMPT, ou direct se sem Mureka)
- [x] Service `LyricsGenerator::Generator` (orquestra Mureka → Claude → save em lyrics_drafts)
- [x] Job `GenerateLyricsJob` (suporta initial + regen)
- [x] Versionamento de prompt (`prompt_version`)
- [x] Log em `GenerationJob` (uma row por chamada Mureka + uma por chamada Claude)
- [x] Testes com WebMock (Mureka + Anthropic)

## 10. Revisão de letra (UI simplificada — ver SPEC 10.1)

- [x] View `/orders/:id/lyrics` — letra como texto corrido, sem blocos editáveis por seção
- [x] Dois botões: "Está perfeita ✓" / "Quero ajustar"
- [x] Campo de texto livre para feedback (quando "Quero ajustar")
- [x] Contador discreto de regenerações restantes
- [x] Stimulus controller mínimo (toggle do feedback form, submit via Turbo)
- [x] Turbo Streams substituem a letra quando o job de regen termina
- [x] Botão "Quero ajustar" desabilitado quando regen_limit atingido
- [x] Endpoint `POST /orders/:id/approve_lyrics` (trava letra + dispara música)
- [x] Endpoint `POST /orders/:id/lyrics/regenerate` (cria nova draft + enfileira job)
- [x] **NÃO implementar:** blocos editáveis, regen por bloco, exposição da JSON structure

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

---

## 19. Revisão de tiers e preços

> Mudança de produto: Standard €29 / Pro €59. Atualizar config e stripe_price_ids.

- [ ] Atualizar `config/brands.yml`: `standard.price_cents: 2900`, `pro.price_cents: 5900`
- [ ] Renomear tier `starter` → `standard` em `brands.yml` (e em todos os fixtures e testes)
- [ ] Adicionar campos ao `brands.yml`: `includes_soundtrack`, `includes_voice_clone` por tier
- [ ] Atualizar fixtures de orders: `tier: "standard"`, `price_cents: 2900`
- [ ] Atualizar seed de voices: `pro_only` agora significa tier `pro` a €59
- [ ] Criar novos Stripe Price IDs para os novos valores (via Stripe dashboard)
- [ ] Atualizar `Stripe::CheckoutBuilder` com os novos price IDs
- [ ] Rodar `bin/rails test` — suite deve ficar verde

---

## 20. Briefing conversacional (substitui wizard)

> Substituir o wizard multi-step por interface de chat. Ver SPEC seção A.

- [ ] Migration: `briefing_messages` (role, content, extracted_briefing jsonb)
- [ ] Model `BriefingMessage` com association `belongs_to :order`
- [ ] Association `has_many :briefing_messages` no model `Order`
- [ ] Service `ConversationalBriefingService < BaseService` (ver SPEC A.2)
  - [ ] Integra com `LyricsGenerator::ClaudeClient` usando system prompt de extração
  - [ ] Salva mensagens user + assistant a cada turn
  - [ ] Faz `order.briefing.update!` com campos extraídos
  - [ ] Retorna `{ reply, suggestions, ready, briefing }`
- [ ] Rota `resource :briefing_chat, only: [:show, :create]` dentro de `resources :orders`
- [ ] `BriefingChatsController` com `show` e `create` (turbo_stream)
- [ ] Views:
  - [ ] `app/views/briefing_chats/show.html.erb` — layout do chat
  - [ ] `app/views/briefing_chats/_message.html.erb` — balão de mensagem (user / assistant)
  - [ ] `app/views/briefing_chats/_suggestions.html.erb` — botões de ação rápida
  - [ ] `app/views/briefing_chats/_cta.html.erb` — botão "Confirmar e pagar" (aparece quando ready: true)
- [ ] Stimulus controller `briefing-chat` (submit do textarea com Enter, scroll automático)
- [ ] Atualizar `OrdersController#new` para criar order + briefing vazios e redirecionar para o chat
- [ ] Deprecar (mas não deletar ainda) as views `orders/wizard/step_*.html.erb`
- [ ] Testes:
  - [ ] Unit: `ConversationalBriefingService` com Claude stubado (WebMock)
  - [ ] Integration: `BriefingChatsController` — turbo stream response

---

## 21. Soundtrack — feature Pro

> Mureka POST /v1/soundtrack/generate. Ver SPEC seção B.

- [ ] Migration: `soundtrack_inputs` (input_type, storage_key, mureka_file_id, mureka_file_status, GDPR fields)
- [ ] Model `SoundtrackInput` com validações e association `belongs_to :order`
- [ ] Association `has_one :soundtrack_input` no model `Order`
- [ ] ActiveStorage attachment para upload do vídeo/imagem (bucket R2 privado)
- [ ] Controller `SoundtrackInputsController` — upload do arquivo pelo cliente Pro
- [ ] Job `UploadSoundtrackInputToMurekaJob` (R2 → POST /v1/files/upload → salva mureka_file_id)
- [ ] Job `GenerateSoundtrackJob` (chama Mureka soundtrack → cria MusicGeneration → enfileira Poll)
- [ ] Método `MurekaClient#generate_soundtrack` (ver SPEC B.3)
- [ ] Lógica de decisão em `Order#start_generation_pipeline!` (ver SPEC B.4)
  - [ ] Atualizar callback `after :pay` na state machine para chamar `start_generation_pipeline!`
- [ ] UI de upload de vídeo/imagem no fluxo Pro (após pagamento confirmado)
- [ ] Validações: tamanho máximo de arquivo, tipos MIME aceitos (image/jpeg, image/png, video/mp4)
- [ ] Job `DeleteSoundtrackInputJob` agendado para `scheduled_deletion_at` (GDPR)
- [ ] Testes:
  - [ ] Unit: `UploadSoundtrackInputToMurekaJob` com WebMock
  - [ ] Unit: `GenerateSoundtrackJob` com WebMock
  - [ ] Unit: `MurekaClient#generate_soundtrack`

---

## 22. Voice cloning — feature Pro

> GDPR-first. Ver SPEC seção C.

- [ ] Migration: `voice_uploads` (storage_key, mureka_file_id, status, consent fields, GDPR fields)
- [ ] Model `VoiceUpload` com validações GDPR obrigatórias
- [ ] Association `has_one :voice_upload` no model `Order`
- [ ] ActiveStorage attachment para o arquivo de voz (bucket R2 privado)
- [ ] Controller `VoiceUploadsController` — upload + registro de consentimento
- [ ] View de upload com checkbox de consentimento explícito (não pré-marcado)
- [ ] Job `UploadVoiceToMurekaJob` (R2 → POST /v1/files/upload?purpose=voice → salva mureka_file_id)
- [ ] Integrar `mureka_file_id` como `vocal_id` no payload do `MusicGenerator::Generator`
- [ ] Job `DeleteVoiceUploadJob` agendado automaticamente para `scheduled_deletion_at` (30 dias após entrega)
- [ ] Testes:
  - [ ] Unit: `UploadVoiceToMurekaJob` com WebMock
  - [ ] Verificar que consent fields são gravados corretamente
  - [ ] Verificar que job de deleção é agendado

---

## Itens fora do MVP (não implementar agora)

- Assinatura recorrente
- App nativo (Hotwire Native)
- SSO/OAuth
- Marketplace de músicas geradas
