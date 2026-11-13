# Roadmap — Music AI Gen

Cronograma de implementação baseado no SPEC.md (seção 19). Marcar tarefas conforme forem concluídas.

**Legenda:** `[ ]` pendente · `[~]` em progresso · `[x]` concluído

**Design de referência:** `design/jinglepro/` — pranchas `*.dc.html` + `canvas.json` + `README.md`, exportadas de um canvas de design em 09/11/2026 (HTML/CSS estáticos que não rodam sozinhos). Substitui o antigo `Plataforma - Vanilla.html`. Toda task de frontend deve consultar a prancha correspondente antes de implementar (mapa prancha → tela em `design/jinglepro/README.md`; ver CLAUDE.md).

**Produto atual:** Campanha JinglePro (pt-BR, BRL, R$ 29,90 via `config/brands.yml`). As seções 7, 19, 20, 21 e 22 abaixo são do app anterior e estão anotadas como LEGADO/superadas; o trabalho em andamento está na **seção 23**.

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
- [x] Definir os estados (14 no desenho original; o model tem 13, `delivered` não foi implementado — ver SPEC 0.4)
- [x] Implementar todas as transições + guards
- [x] Callbacks `after` (jobs e mailers)
- [x] Testes de todas as transições válidas e inválidas

## 5. Brand/Locale resolver

> Estado atual: marca única `b2b` (a JinglePro) e locale sempre `pt` (o `ApplicationController` descarta o locale que o resolver calcula). `BrandConstraint` foi removido. Ver CLAUDE.md, "Marca e locale".

- [x] Service `BrandLocaleResolver` (detecta brand+locale por host)
- [x] `before_action` no `ApplicationController` setando `@brand` e `I18n.locale`
- [x] Routes com `constraints` por host
- [x] Helper `t_brand(key)` em `ApplicationHelper`
- [x] Setup multi-host em `development` (hosts file ou similar)

## 6. Seed do catálogo de vozes

- [x] `db/seeds/voices.rb` com vozes placeholder
- [x] `db/seeds.rb` chamando o arquivo de vozes

## 7. Wizard de briefing

> **LEGADO.** O briefing da Campanha é o formulário de `/campaigns/new`. O wizard continua no código até a fatia 5 (seção 23).

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

- [x] **M-1**: HTTPS obrigatório em produção; `assume_ssl` somente com `BEHIND_SSL_PROXY=true`, definido pelo deploy Kamal com TLS
- [x] **M-3**: `config.hosts` restrito ao `APP_HOST` exato da marca única; origem do Checkout também vem dessa configuração
- [ ] **M-7**: Adicionar `before_send` no Sentry filtrando query strings (evitar vazar `confirmation_token`/`reset_password_token` em traces)
- [x] **B-2**: Remetente via `MAILER_FROM`, links HTTPS via `APP_HOST`, SMTP Resend via `RESEND_API_KEY`; produção valida as variáveis obrigatórias

### Antes do frontend ir para staging

- [x] **M-2**: CSP ativa com nonce para scripts/importmap; mantém estilos inline legados e origens específicas de fontes, mídia e checkout

### Antes da Seção 14 (Storage / R2)

- [ ] **M-4**: Trocar `config.active_storage.service = :local` para `:r2` em `production.rb`

### Após primeiros controllers autenticados

- [ ] **M-6**: Adicionar `after_action :verify_authorized` + `:verify_policy_scoped` no ApplicationController (com skip para Devise controllers)

### Hardening incremental (sem urgência)

- [x] **B-1**: Chaves Stripe em branco nos exemplos; nenhum segredo real versionado
- [x] **B-4**: `SENTRY_DSN` vazio tratado com `.presence`
- [x] **B-5**: `:card_number` e `:iban` filtrados nos parâmetros de log
- [ ] **B-6**: Criar `config/initializers/session_store.rb` explícito quando `force_ssl` estiver ativo

### Achados da revisão de segurança do Criar (13/11/2026, anteriores ao redesign)

- [ ] **S-1** (médio): `campaign[photos][]` aceita string. Lixo dá 500 (`InvalidSignature`) e o signed id de um blob de outro usuário é anexado. Filtrar para `ActionDispatch::Http::UploadedFile` em `CampaignsController#campaign_params`
- [ ] **S-2** (médio): `Campaign#supported_photo` confia no `content_type` declarado; texto declarado `image/jpeg` passa, o cliente paga e o vídeo falha. Validar magic bytes com Marcel
- [ ] **S-3** (médio, decisão de produto): sem rate limit em `POST /campaigns` e `orders#checkout`, sem limpeza de pedidos `pending` abandonados, e voltar da Stripe pelo bfcache pode criar outro pedido
- [ ] **S-4** (baixo): `photo_order=` usa `Integer(id, exception: false)` (aceita `"0x2cb"`); usar base 10. `media_src` aceita qualquer `https:`

---

---

## 19. Revisão de tiers e preços

> **SUPERADO.** Esta revisão (Standard €29 / Pro €59) não vale mais: o produto é a Campanha a R$ 29,90 (`tiers.starter` em `config/brands.yml`; não usa `stripe_price_ids`, o Checkout cria o preço com `price_data`). Mantido como registro; não executar.
>
> Descrição original: Standard €29 / Pro €59. Atualizar config e stripe_price_ids.

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

> **LEGADO.** O chat foi implementado em parte (`OrderChat`, `ConversationalBriefingService`, `BriefingMessage`) mas está fora do produto atual; a remoção do código morto é a fatia 5 (seção 23). Os itens abaixo não devem ser retomados.
>
> Descrição original: Substituir o wizard multi-step por interface de chat. Ver SPEC seção A.

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

> **LEGADO.** Fora do produto atual; o código existente (`SoundtrackInput` e jobs) sai na fatia 5 (seção 23). Não retomar.
>
> Descrição original: Mureka POST /v1/soundtrack/generate. Ver SPEC seção B.

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

> **LEGADO, nunca implementado.** Não existe `VoiceUpload` no código e o SPEC (seção 21) proíbe a funcionalidade. Não retomar.
>
> Descrição original: GDPR-first. Ver SPEC seção C.

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

## 23. Redesign JinglePro (fatias 0–5)

> Em andamento na branch `redesign/jinglepro`. Referência: `design/jinglepro/` (o README dela mapeia cada prancha à tela do app). O mapeamento de estados que as fatias 1 e 3 implementam está no SPEC, seção 0.4. Cada fatia passa pelo fluxo de agentes do CLAUDE.md.

- [~] **Fatia 0, baseline + docs**
  - [x] CLAUDE.md, SPEC.md, README.md e ROADMAP.md alinhados com o produto Campanha (alterações no working tree, ainda sem commit)
  - [ ] Commit do baseline do working tree
  - [ ] Versionar `design/jinglepro/` (hoje não rastreada pelo git)
- [ ] **Fatia 1, CSS único, landing, Entrar, Biblioteca, Estados**
  - [ ] Unificar `landing.css`, `studio.css`, `studio_app.css` e `studio_identity.css` em um CSS único com tokens `--jp-*` (destino do Tailwind a decidir)
  - [ ] Landing (`pages/home`; pranchas `Main` e `Landing-Mobile`)
  - [ ] Entrar (`users/sessions/new` e telas de senha; prancha `Entrar`)
  - [ ] Biblioteca (`songs/index`; prancha `Biblioteca`) com os estados Aguardando pagamento, Em criação (fase N de 3), Pronta e Precisa de atenção (SPEC 0.4). "Precisa de atenção" ainda não foi desenhado
  - [ ] Estados vazio e de erro (prancha `Estados`)
- [~] **Fatia 2, reskin do Criar** (branch `feat/criar-caminho-b`; design `docs/superpowers/specs/2026-11-13-criar-caminho-b-design.md`)
  - [x] Passos 1, 2 e 3 de `campaigns/new` com `ui.css` e sem `studio-app` (tarefas 1 a 9 do plano)
  - [ ] Commit, PR e merge
  - [ ] Tarefa 10: atualizar a linha de CSS do CLAUDE.md e a seção "Campanha" do SPEC (depois do merge)
  - [ ] Pendências do passe visual: cabeçalho compartilhado quebra em 2 linhas no celular (133 px contra 64 px da prancha); no celular o player do passo 2 fica abaixo dos 12 ritmos; o botão "Ver prévia" cobre o contador da oferta na primeira dobra
  - [ ] Conferir visualmente os estados `payment_failed`, checkout iniciado e erro 422 do servidor (só têm cobertura de integração)
  - [ ] Limpar CSS órfão: `.campaign-sound-fields`, `.campaign-sound-details`, `.jp-genres`, `.campaign-style*`, `.campaign-review-photo`, `.campaign-total`, `.campaign-included`
- [x] **Fatia 3, Estúdio em 3 fases e Entrega** (branch `feat/estudio-caminho-b`; design `docs/superpowers/specs/2026-11-13-estudio-caminho-b-design.md`)
  - [x] Estúdio em 3 fases: letra, músicas, vídeo (pranchas `Estudio` e `Estudio-Mobile`), com a derivação de fase em `Campaigns::StudioPhase`
  - [x] Ações do estúdio ficam em `order_chat#*` (rotas inalteradas); só as views novas em `order_chat/studio/`. A remoção do chat continua na fatia 5
  - [x] Prévia da música inteira com marca sonora (`campaign_audio#full`, `OrderAsset#full_audition_audio`)
  - [x] Entrega (`campaigns/_delivery`; prancha `Entrega`) e acompanhamento do vídeo com a casca do estúdio
  - [x] Imagens em broadcasts Turbo usam URL só com o caminho; antes saíam com o host `example.org` do renderizador
  - [ ] Fora da fatia: a Biblioteca (`songs#index`) ainda não usa `Campaigns::StudioPhase` (fatia 1)
  - [ ] O estúdio segue sob a rota legada `/orders/:id/chat` (`order_chat`), que só sai com a fatia 5
  - [ ] **Deploy:** depois de subir a marca d'água `Campaigns::AudioAudition::VERSION` 2, rodar `bin/rails campaigns:prepare_auditions`. Sem isso, os pedidos ainda não aprovados ficam com "Prepare a amostra para ouvir" em cada versão e "Gerar meu vídeo" desligado até o lojista preparar cartão por cartão. A task só pega campanhas não aprovadas e versões sem a amostra da versão atual, e pode rodar de novo
  - [ ] "Prévia completa sendo preparada" usa uma heurística de 10 minutos; se aparecerem casos travados, criar `full_audition_status`. Ela também dá falso positivo logo depois de trocar o trecho na fase 3 (o `ExcerptSettings` refaz a `audition_audio` pelo `PrepareCampaignAudioJob`): por até 10 minutos uma versão antiga sem prévia completa não mostra o link nem "Preparar música completa" (revisão final, M7)
  - [ ] Várias versões se chamam "Versão A" em `h2` (uma por rodada); a rodada só aparece no texto sr-only do rádio. Pôr a rodada no título das rodadas anteriores (revisão final, M11)
  - [ ] Sem teste de sistema para um broadcast durante a reprodução (RF 1 só cobre digitação; revisão final, M4)
  - [ ] O ramo `"custom"` de `order_chat#excerpt_settings` não tem mais UI; sai com a fatia 5, junto com os testes legados que ainda o usam
  - [ ] Borda rara: `video_status` `ready` sem vídeo anexado mostra "Entrega" no topo e "Montando" no corpo, sem polling
  - [ ] Prompt da Mureka: no teste real de 13/11/2026 a faixa veio com cerca de 16 s de introdução sem voz, e faixas de 66 s e 163 s para um pedido de 30 s. Investigar o prompt e a duração antes de prometer o trecho ao lojista
- [ ] **Fatia 4, conta e pagamento no passo 3**
  - [ ] Passo 3 do Criar com criação de conta e botão "Pagar" (hoje o cadastro vem antes do formulário via `orders#new`)
  - [ ] Decidir como retomar um pedido em `payment_failed` (hoje checkout e edição só aceitam `pending`)
  - [ ] Consentimento junto ao botão "Pagar" e e-mail já cadastrado ainda não foram desenhados
- [ ] **Fatia 5, remoção do código morto do chat**
  - [ ] Remover chat conversacional (`ConversationalReplyJob`, `ConversationalBriefingService`, `BriefingMessage`, views de conversa de `order_chat/`), soundtrack, wizard de 5 passos e seus testes, depois que a fatia 3 tiver migrado as ações do estúdio
  - [ ] Confirmar se `lyrics#*`, `music_preview#*`, `orders#show` e `orders/:id/spf/*` também saem (SPEC 0.7)

---

## Itens fora do MVP (não implementar agora)

- Assinatura recorrente
- App nativo (Hotwire Native)
- SSO/OAuth
- Marketplace de músicas geradas
