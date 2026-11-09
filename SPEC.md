Spec Técnico — Plataforma de Geração de Música com AI

> **Última atualização: 2026-11-09** — Produto único: **Campanha JinglePro** (pt-BR, BRL). A **seção 0** é a fonte de verdade do produto atual. As seções 1 a 4 e 18 descrevem o app anterior (Europa, tiers em €, chat, soundtrack, voz) e as seções A, B e C são **LEGADO**: cada uma traz um aviso onde contradiz o código. Quando houver conflito entre a seção 0 e o resto, vale a seção 0.

## 0. Campanha JinglePro (produto atual)

### 0.1 O que é

O lojista informa a oferta do negócio e envia até 5 fotos, paga uma vez via Stripe Checkout, revisa e edita a letra, escolhe entre 2 músicas por rodada (até 3 rodadas) e recebe um vídeo vertical 9:16 (MP4) + a música em MP3 + uma legenda sugerida. Mercado: Brasil, interface em pt-BR, moeda BRL, pagamento único, sem assinatura.

- **Preço:** R$ 79 hoje. Vem de `config/brands.yml` (`b2b.campaign_tier: starter` → `tiers.starter.price_cents: 7900`, `currency: BRL`) e é exibido por `campaign_price`. Nunca hardcoded. `CampaignsController#create` copia `price_cents`, `currency`, `lyrics_regen_limit` e `music_regen_limit` para o `Order`; mudar o YAML não altera pedidos existentes.
- **Marca:** existe uma só, com identificador interno `b2b` (nome herdado: é a JinglePro, não um segmento B2B). Ver CLAUDE.md, "Marca e locale".
- **Arquitetura:** Rails monolito + Hotwire. Sem SPA.

### 0.2 Fluxo do lojista

Descreve o código atual (fatia 0 do redesign). Onde o redesign muda o fluxo, a nota diz em qual fatia.

1. **Entrada.** `GET /` (`pages#home`). O CTA vai para `GET /orders/new`, que **não cria pedido**: visitante sem sessão é enviado ao cadastro (`/users/sign_up`) com `/campaigns/new` guardado como destino; usuário logado vai direto para `/campaigns/new`. (Fatia 4: conta e pagamento passam para o passo 3 do Criar.)
2. **Criar.** `GET /campaigns/new` → `POST /campaigns`. Campos: nome do negócio (até 60 caracteres), oferta (180), contato (70), chamada para ação (40, padrão "Peça pelo WhatsApp"), até 5 fotos (JPG, PNG ou WebP, até 10 MB cada, com ordem escolhida), ritmo (10 opções + "escolher por mim"), voz (automática, feminina ou masculina), clima (`style`: animado, acolhedor ou marcante) e direção adicional (até 240). Cria `Order` em `pending`, `Campaign` e `Briefing` (`Campaign#sync_briefing!`). A edição (`campaigns#edit/update`) só é aceita enquanto o pedido está `pending` e sem `stripe_session_id`.
3. **Confirmar e pagar.** `GET /campaigns/:id` (pedido `pending`) mostra o resumo e o botão que faz `POST /orders/:id/checkout` → Stripe Checkout (`mode: payment`, cartão, um item "JinglePro — Campanha com música e vídeo"). O pagamento é confirmado pelo webhook `checkout.session.completed` ou pela reconciliação em `campaigns#show` (`Stripe::PaymentReconciler`); ambos chamam `Stripe::CheckoutFulfillment` → `mark_paid!` → `GenerateLyricsJob`. Visitar a URL de sucesso não confirma pagamento. Em development existe `POST /campaigns/:id/test_payment` ("Testar sem cobrança").
4. **Estúdio.** Hoje renderizado em `/orders/:order_id/chat` (`order_chat#show`, partial `_campaign_studio`); a fatia 3 o reorganiza em 3 fases:
   - **Fase 1, letra.** A Mureka gera a letra (`LyricsGenerator::Generator` → `MurekaLyricsClient`). O lojista edita à mão (`Campaigns::LyricsEditor`, cria um `LyricsDraft` com `source: "user_edited"`, não gasta rodada nem ajuste) ou pede reescrita por IA (`RewriteCampaignLyricsJob`, consome `lyrics_regen_used` até `lyrics_regen_limit`, 20 hoje). Aprovar a letra leva a `lyrics_approved`.
   - **Fase 2, músicas.** `Campaigns::MusicRounds` reserva a rodada sob lock e enfileira `GenerateCampaignMusicJob` (Mureka, modelo `mureka-9`, `n: 2`). Cada rodada traz 2 versões (A e B). Cada versão ganha um trecho de até 30 s (`PrepareCampaignAudioJob`) cujo início o lojista pode ajustar antes de aprovar. É possível marcar uma favorita e pedir nova rodada com direção de mudança. Aprovar uma versão de qualquer rodada leva a `approved`.
   - **Fase 3, vídeo.** `Campaign#queue_video!` → `RenderCampaignVideoJob`: `video_status` vai de `queued` a `rendering` e termina em `ready` ou `failed`.
5. **Entrega.** `campaigns/_delivery` mostra o vídeo, o link `GET /campaigns/:id/download` (MP4), o MP3 da versão aprovada e a legenda sugerida (`Campaign#caption`). `GET /campaigns/:id/status` serve o polling enquanto o vídeo é montado.
6. **Biblioteca.** `GET /songs` (`songs#index`) lista as campanhas do usuário. Ver 0.4.

### 0.3 Limites e parâmetros

| Parâmetro | Valor | Origem |
|---|---|---|
| Rodadas de música completas | 3 | `Campaigns::MusicRounds::LIMIT` |
| Versões por rodada | 2 | `n: 2` em `MusicRounds` |
| Modelo musical | `mureka-9` | `Campaigns::MusicRounds::MODEL` |
| Reescritas de letra por IA | 20 | `brands.yml`, `tiers.starter.lyrics_regen_limit`, copiado para `orders.lyrics_regen_limit` |
| Edições manuais da letra | sem limite (até 5.000 caracteres) | `Campaigns::LyricsEditor` |
| Fotos por campanha | até 5, 10 MB cada | validações de `Campaign` |
| Trecho de áudio / vídeo | até 30 s | `Campaigns::AudioPreview::MAX_DURATION` |
| Vídeo | MP4 720x1280, 24 fps, H.264 + AAC | `Campaigns::VideoRenderer` |
| Teto técnico de custo | 5 pares potencialmente cobrados e 12 envios por campanha | `MusicRounds::MAX_PAID_ATTEMPTS`, `MAX_REQUESTS` |

Falhas de geração não consomem rodada: só uma rodada com 2 músicas válidas é contada (`Order#completed_music_rounds`). Custos estimados de API são gravados em `generation_costs`; `bin/rails campaigns:costs` exporta o CSV.

### 0.4 Mapeamento de estados: Order + `video_status` → estúdio e Biblioteca

`Order::STATUSES` tem 13 valores. O vídeo tem estado próprio em `campaigns.video_status` (`pending`, `queued`, `rendering`, `ready`, `failed`). O estado `approved` **não basta** para saber se a campanha está pronta: sempre cruze com `video_status`.

| `Order.status` | `video_status` | Fase do estúdio | Estado na Biblioteca |
|---|---|---|---|
| `pending` | `pending` | Fora do estúdio: tela de confirmação `/campaigns/:id` (com `?payment=processing`: "Aguardando a confirmação do pagamento") | **Aguardando pagamento** ("Pagar" e "Editar dados") |
| `payment_failed` | `pending` | Fora do estúdio | **Aguardando pagamento** |
| `paid` | `pending` | Fase 1 de 3, "preparando a letra" | **Em criação**, fase 1 de 3 |
| `lyrics_drafting` | `pending` | Fase 1 de 3, "preparando a letra" | **Em criação**, fase 1 de 3 |
| `lyrics_ready` | `pending` | Fase 1 de 3: revisar, editar, reescrever, aprovar | **Em criação**, fase 1 de 3 |
| `lyrics_approved` | `pending` | Fase 2 de 3, "criando duas versões" | **Em criação**, fase 2 de 3 |
| `music_generating` | `pending` | Fase 2 de 3, "criando duas versões" | **Em criação**, fase 2 de 3 |
| `preview_ready` | `pending` | Fase 2 de 3: ouvir, ajustar corte, favoritar, aprovar ou nova rodada | **Em criação**, fase 2 de 3 |
| `approved` | `pending`, `queued` ou `rendering` | Fase 3 de 3, "montando o vídeo" | **Em criação**, fase 3 de 3 |
| `approved` | `ready` | Entrega ("Campanha pronta") | **Pronta** ("Baixar vídeo" e "Ver campanha") |
| `approved` | `failed` | Fase 3 de 3, falha do vídeo ("A música está salva"; tentar montar de novo) | **Precisa de atenção** |
| `lyrics_failed` | `pending` | Fase 1 de 3, "a letra não ficou pronta"; `POST /campaigns/:id/retry_generation` | **Precisa de atenção** |
| `music_failed` | `pending` | Fase 2 de 3, falha da rodada; "Tentar novamente" / "Verificar tentativa", ou aprovar uma versão já pronta | **Precisa de atenção** |
| `cancelled`, `refunded` | qualquer | n/a | **Oculto** (não aparece na Biblioteca) |

Notas:
- `paid` e `lyrics_approved` são estados transitórios; a atribuição de `lyrics_approved` à fase 2 é decisão de apresentação, a confirmar na fatia 3.
- `approved` com `video_status == "pending"` é transitório (o aprovador chama `queue_video!` logo depois) e deve ser tratado como fase 3.
- Quando `music_failed` ou `lyrics_failed` ocorre numa campanha com rodadas anteriores, as versões anteriores continuam disponíveis; "precisa de atenção" não significa "perdido".
- **Hoje (fatia 0)**, `SongsController#index` lista pedidos `approved` e qualquer pedido com campanha fora de `cancelled`/`refunded`, e a view só distingue "Ver campanha pronta" de "Acompanhar criação". Os rótulos acima (fase N de 3, aguardando pagamento, precisa de atenção) são alvo das fatias 1 e 3. O estado "Precisa de atenção" ainda não foi desenhado (ver `design/jinglepro/README.md`).
- **A confirmar:** `payment_failed` é gravado por `Stripe::Handlers::PaymentIntentFailed` com `update_columns`, mas `OrdersController#checkout` e `CampaignsController#edit/update/show` só tratam `pending`. Como o lojista volta a pagar nesse estado precisa ser decidido na fatia 4.
- A regra de derivação (status + `video_status` → fase e estado) deve morar em um só lugar, usado pelo estúdio e pela Biblioteca, para os dois nunca divergirem.

Transições AASM do `Order` (eventos em `app/models/order.rb`): `mark_paid` (`pending`→`paid`), `start_lyrics_generation` (→`lyrics_drafting`), `lyrics_drafted` (→`lyrics_ready`), `approve_lyrics` (→`lyrics_approved`), `start_music_generation` (→`music_generating`), `music_ready` (→`preview_ready`), `approve_music` (`preview_ready`→`approved`), `regenerate_music` (`preview_ready`→`music_generating`), `fail_lyrics`, `fail_music`, `cancel` e `refund` (`cancelled`→`refunded`). No fluxo da campanha, `Orders::MusicApprover`, `Campaigns::MusicRounds` e `CampaignsController#retry_generation` também gravam `status` direto com `update!`; `payment_failed` nunca passa por evento.

### 0.5 Modelo de dados da campanha

- `campaigns` (1:1 com `orders`, `order_id` único): `business_name`, `offer`, `contact`, `call_to_action`, `style`, `musical_genre`, `vocal_gender`, `music_notes`, `photo_order` (jsonb, ids dos anexos), `video_status`, `video_error`. Anexos Active Storage: `photos` (vários, até 5), `photo` (foto única de campanhas antigas), `video`, `poster`.
- Reaproveita `orders`, `briefings`, `lyrics_drafts`, `music_generations`, `order_assets` (`kind: "music_variant"`), `stripe_events`.
- Novas tabelas: `business_music_profiles` (identidade musical por usuário e nome de negócio normalizado, via `Campaigns::SaveMusicProfile`) e `generation_costs` (custo estimado de API por evento).
- Colunas de controle no `orders`: `favorite_music_asset_id`, `lyrics_revision_token` e `lyrics_revision_error`.

### 0.6 Rotas da campanha

| Rota | Controller#ação | Função |
|---|---|---|
| `GET /` | `pages#home` | Landing |
| `GET /orders/new` | `orders#new` | Redireciona para cadastro ou `/campaigns/new`; não cria pedido |
| `GET/POST /campaigns/new`, `/campaigns` | `campaigns#new/create` | Criar |
| `GET /campaigns/:id` | `campaigns#show` | Confirmar e pagar; entrega |
| `GET/PATCH /campaigns/:id/edit`, `/campaigns/:id` | `campaigns#edit/update` | Editar dados (só `pending`, sem sessão Stripe) |
| `POST /orders/:id/checkout` | `orders#checkout` | Abre o Stripe Checkout |
| `POST /stripe/webhook` | `stripe#webhook` | Webhook (200 se a assinatura é válida; processamento assíncrono) |
| `GET /campaigns/:id/status` | `campaigns#status` | Polling do vídeo (Turbo Stream) |
| `POST /campaigns/:id/render_video` | `campaigns#render_video` | Montar o vídeo de novo |
| `POST /campaigns/:id/retry_generation` | `campaigns#retry_generation` | Retentar letra ou música |
| `GET /campaigns/:id/download` | `campaigns#download` | Baixar o MP4 |
| `POST /campaigns/:id/save_music_profile` | `campaigns#save_music_profile` | Salvar o som do negócio |
| `/orders/:order_id/chat/*` | `order_chat#*` | Estúdio atual (letra, rodadas, favorita, trecho). Muda na fatia 3 |
| `GET /songs` | `songs#index` | Biblioteca |

### 0.7 LEGADO (código presente, fora do produto)

Não construir nada novo sobre estes itens. A remoção do código morto do chat é a fatia 5 do redesign (ROADMAP).

- **Chat conversacional:** `OrderChatController#create` (`handle_chat_message`), `ConversationalReplyJob`, `ConversationalBriefingService`, `BriefingMessage` (`briefing_messages`) e as views de conversa de `order_chat/`. Esse controller **também hospeda hoje as ações do estúdio** (aprovar e editar letra, rodadas, favorita, trecho, direção musical): elas precisam migrar na fatia 3 antes da remoção. O LLM do chat é a OpenAI `gpt-4o-mini` (classe `LyricsGenerator::ClaudeClient`, nome herdado). Ver seção A.
- **Soundtrack:** `SoundtrackInput`, `SoundtrackInputsController`, `UploadSoundtrackInputToMurekaJob`, `GenerateSoundtrackJob`, `DeleteSoundtrackInputJob`, `Order#start_soundtrack_generation` e o tier `pro` de `brands.yml`. Ver seção B.
- **Voice cloning:** nunca implementado (não existe model `VoiceUpload`). A seção C e o tier `pro` ficam só como registro; a seção 21 já proíbe a funcionalidade. O catálogo `Voice` **continua em uso** (`Campaign#sync_briefing!` escolhe a voz padrão do briefing).
- **Wizard de 5 passos:** `orders#wizard_show/wizard_update`, rotas `/orders/wizard/:step`, views `orders/wizard/step_1` a `step_5`, `Orders::WizardSession`, `Orders::StepValidator`, `Orders::CreateDraftService` e os Stimulus `wizard_tier` e `wizard_voice`.
- **A confirmar na fatia 5** (parecem fluxos de pedido sem campanha): `lyrics#*`, `music_preview#*`, `orders#show` e as rotas `orders/:id/spf/*`.

### 0.8 Onde o resto do SPEC diverge do código

| Seção | O que diz | O que o código faz hoje |
|---|---|---|
| 1, 3, 4, 18 | Europa, multi-idioma, tiers `standard`/`pro` em € (€29/€59), B2B + B2C | Brasil, pt, BRL; `brands.yml` tem só `b2b` com tiers `starter` (R$ 79) e `pro` (legado); locale efetivo sempre `pt` |
| 2, 13 | LLM de letras: Anthropic Claude | Letras: só Mureka (`/v1/lyrics/generate`), inicial e reescrita. O único LLM é a OpenAI `gpt-4o-mini`, no chat legado |
| 2, 15 | Storage em Cloudflare R2, buckets público e privado, signed URLs de 1h | Disk (`config/storage.yml`); download via `campaigns#download`. R2 é meta (ROADMAP, M-4) |
| 2, 16 | Emails transacionais por brand e locale (Postmark ou Resend) | Só mailers do Devise. `OrderMailer` e o model `EmailDelivery` foram removidos (a tabela `email_deliveries` continua no schema); sem provedor configurado |
| 7 | "Sidekiq jobs" | Solid Queue (`:solid_queue` em production, `:async` em development) |
| 8 | 14 estados, inclusive `delivered` | 13 estados; `delivered` não existe em `Order::STATUSES` |

---

1. Visão geral

> **LEGADO / desatualizado.** Substituída pela seção 0. O texto abaixo descreve o app europeu anterior (chat conversacional, tiers em €, soundtrack e voz clonada no Pro).

Plataforma web (Rails 8 + Hotwire) para pequenos comerciantes europeus criarem música original para redes sociais (Reels, TikTok, Instagram, ads). Cliente descreve o negócio via chat conversacional, paga via Stripe, revisa a letra gerada por AI, aprova e recebe duas variantes de música para escolher. Tier Pro inclui geração de soundtrack sincronizado com vídeo/imagem e clonagem de voz.

Mercado: Europa, com Itália como mercado principal. Multi-idioma desde o início (it, en, es, fr, de, pt).
Arquitetura: Rails 8 monolito + Hotwire + Tailwind. Sem SPA, sem frontend separado.

2. Stack técnica

> **Desatualizada em parte.** A stack conferida contra o código está no CLAUDE.md (seção Stack). Divergências: letras só pela Mureka (sem Anthropic), storage em Disk (R2 é meta), email sem provedor configurado, Ruby 4.0.5. Ver 0.8.

Backend: Ruby on Rails 8, PostgreSQL 16+
Frontend: Hotwire (Turbo + Stimulus), Tailwind CSS 4
Auth: Devise + Pundit
Background jobs: Solid Queue
Pagamento: Stripe Checkout + webhooks
Storage: ActiveStorage com S3-compatible (Cloudflare R2)
Email: Postmark ou Resend (transacional)
Processamento áudio: FFmpeg (server-side, via shell)
AI providers:

Letras: Mureka API (POST /v1/lyrics/generate) + Anthropic Claude (claude-opus-4-7) para refino
Música: Mureka API (POST /v1/song/generate)
Soundtrack: Mureka API (POST /v1/soundtrack/generate) — Pro only
Voice cloning: Mureka API (POST /v1/files/upload com purpose: "voice") — Pro only


Deploy: Kamal 2 (Docker)
Monitoring: Sentry

3. Modelo de negócio

> **LEGADO / desatualizado.** Preços em €, tiers `standard`/`pro` e fluxo com `delivered` não valem mais. O produto atual (R$ 79, tier `starter` de `config/brands.yml`) está na seção 0. O tier `pro` (soundtrack e voz clonada) é LEGADO.

Marca única: B2B — JinglePro (jinglepro.it / jinglepro.com)

Tiers e preços:
yaml
b2b:
  tiers:
    standard:
      price_cents: 2900        # €29
      description: "Jingle personalizado com letra para redes sociais"
      lyrics_regen_limit: 2
      music_regen_limit: 2
      includes_stems: false
      includes_soundtrack: false
      includes_voice_clone: false
      max_duration_seconds: 30

    pro:
      price_cents: 5900        # €59
      description: "Jingle + soundtrack sincronizado com vídeo + voz clonada"
      lyrics_regen_limit: 3
      music_regen_limit: 3
      includes_stems: true
      includes_soundtrack: true    # POST /v1/soundtrack/generate
      includes_voice_clone: true   # vocal_id via files/upload
      max_duration_seconds: 60

Preços e limites configuráveis via YAML, NÃO hardcoded. Cada pedido cacheia os limites no DB no momento da compra.
Fluxo do cliente — Standard
1. pending           → briefing conversacional preenchido, aguardando pagamento
2. paid              → Stripe webhook confirmou pagamento
3. lyrics_drafting   → AI gerando letra
4. lyrics_ready      → letra disponível para revisão
5. lyrics_approved   → cliente aprovou letra (TRAVADA)
6. music_generating  → Mureka gerando 2 variantes de música
7. preview_ready     → cliente pode ouvir os previews
8. approved          → cliente escolheu uma variante
9. delivered         → arquivo final disponível para download

Fluxo do cliente — Pro com vídeo (soundtrack)
Após paid: skip do fluxo de letra → UploadSoundtrackInputToMurekaJob → music_generating → preview_ready → approved → delivered

Estados de falha: payment_failed, lyrics_failed, music_failed, cancelled, refunded

4. Modelo de domínios

> **LEGADO / desatualizado.** O código não escolhe mais locale por host: `BrandLocaleResolver#detect_brand` sempre retorna `b2b`, e `ApplicationController` descarta o locale calculado e usa `pt` (`brands.yml` → `default_locale`). Ver CLAUDE.md, "Marca e locale".

B2B:
- jinglepro.it       → b2b, locale it (forçado)
- jinglepro.com      → b2b, locale detectado por Accept-Language
Rails seta I18n.locale via before_action. Brand sempre "b2b".

---

## A. Briefing conversacional

> **LEGADO.** O produto atual usa o formulário de `/campaigns/new` (seção 0.2), não um chat. Este código (`OrderChat`, `ConversationalReplyJob`, `ConversationalBriefingService`, `BriefingMessage`) continua no repositório até a fatia 5 do redesign. O LLM real é a OpenAI `gpt-4o-mini` (via `LyricsGenerator::ClaudeClient`), não o Claude descrito abaixo, e `BriefingChatsController` e a rota `briefing_chat` descritos em A.3 não existem (o chat roda em `order_chat#*`). Texto original preservado como registro.

Em vez do wizard multi-step, o cliente descreve o projeto via chat. Um assistente AI (Claude) extrai os campos do briefing naturalmente e retorna também sugestões de botões rápidos.

### A.1 Schema

```ruby
create_table :briefing_messages do |t|
  t.references :order, foreign_key: true, null: false
  t.string :role, null: false          # "user" | "assistant"
  t.text :content, null: false
  t.jsonb :extracted_briefing          # snapshot dos campos extraídos neste turn
  t.timestamps
end
```

### A.2 ConversationalBriefingService

```ruby
# app/services/conversational_briefing_service.rb
class ConversationalBriefingService < BaseService
  SYSTEM_PROMPT = <<~PROMPT
    You are a friendly music creation assistant for small business owners.
    Extract briefing info from the conversation naturally.
    Never ask more than one question per turn.
    Keep replies short and warm, max 3 sentences.
    Suggest 2-3 quick options as buttons when relevant.

    Return ONLY valid JSON:
    {
      "reply": "friendly message to show user",
      "suggestions": ["quick option 1", "quick option 2"],
      "ready": false,
      "briefing": {
        "about": "...",
        "recipient": "...",
        "occasion": "...",
        "keywords": "...",
        "avoid": "...",
        "music_style": "...",
        "mood": "...",
        "tempo": "...",
        "language": "it",
        "target_duration_seconds": 30
      }
    }

    Set "ready": true only when you have: about, music_style, mood, language, target_duration_seconds.
    Never expose technical field names to the user.
  PROMPT

  attribute :order
  attribute :new_message, :string

  def call
    history = order.briefing_messages.map { |m| { role: m.role, content: m.content } }

    response = LyricsGenerator::ClaudeClient.chat(
      system: SYSTEM_PROMPT,
      messages: history + [{ role: "user", content: new_message }]
    )

    parsed = JSON.parse(response[:content])

    order.briefing_messages.create!(role: "user", content: new_message)
    order.briefing_messages.create!(
      role: "assistant",
      content: parsed["reply"],
      extracted_briefing: parsed["briefing"]
    )
    order.briefing.update!(parsed["briefing"].compact) if parsed["briefing"].present?

    success_result(parsed)
  end
end
```

### A.3 Rotas e controller

```ruby
# config/routes.rb
resources :orders do
  resource :briefing_chat, only: [:show, :create]
end

# app/controllers/briefing_chats_controller.rb
class BriefingChatsController < ApplicationController
  before_action :authenticate_user!

  def show
    @order = current_user.orders.find(params[:order_id])
    @messages = @order.briefing_messages
    @briefing = @order.briefing
  end

  def create
    @order = current_user.orders.find(params[:order_id])
    result = ConversationalBriefingService.call(order: @order, new_message: params[:message])

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("messages", partial: "briefing_chats/message",
            locals: { role: "user", content: params[:message] }),
          turbo_stream.append("messages", partial: "briefing_chats/message",
            locals: { role: "assistant", content: result.value["reply"] }),
          turbo_stream.replace("suggestions", partial: "briefing_chats/suggestions",
            locals: { suggestions: result.value["suggestions"] }),
          turbo_stream.replace("cta", partial: "briefing_chats/cta",
            locals: { ready: result.value["ready"], order: @order })
        ]
      end
    end
  end
end
```

---

## B. Soundtrack — feature Pro

> **LEGADO.** Fora do produto atual (a Campanha usa fotos para o vídeo, não para gerar a música). O código (`SoundtrackInput`, `SoundtrackInputsController`, `UploadSoundtrackInputToMurekaJob`, `GenerateSoundtrackJob`, `DeleteSoundtrackInputJob`) fica até a fatia 5. Texto original preservado como registro.

Cliente Pro faz upload de imagem ou vídeo do negócio. A Mureka gera a música sincronizada com o visual.

### B.1 Schema

```ruby
create_table :soundtrack_inputs do |t|
  t.references :order, foreign_key: true, null: false
  t.string :input_type, null: false      # "image" | "video"
  t.string :storage_key, null: false     # chave no bucket R2 privado
  t.string :mureka_file_id               # retornado pelo POST /v1/files/upload
  t.string :mureka_file_status           # "pending" | "ready" | "failed"
  t.integer :file_size_bytes
  t.string :mime_type
  t.integer :duration_seconds            # só para vídeo
  t.datetime :scheduled_deletion_at      # GDPR — 30 dias após entrega
  t.datetime :deleted_at
  t.timestamps
end
```

### B.2 Jobs

```ruby
# 1. Upload do arquivo para Mureka (após pagamento Pro com vídeo/imagem)
class UploadSoundtrackInputToMurekaJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    input = order.soundtrack_input
    # download do R2 → POST /v1/files/upload → salva mureka_file_id
    # quando ready: enfileira GenerateSoundtrackJob
  end
end

# 2. Geração do soundtrack
class GenerateSoundtrackJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    input = order.soundtrack_input
    response = MusicGenerator::MurekaClient.call(
      action: :soundtrack,
      file_id: input.mureka_file_id,
      input_type: input.input_type,
      prompt: order.briefing.about,
      n: 2
    )
    # cria MusicGeneration + enfileira PollMurekaStatusJob
  end
end
```

### B.3 Método MurekaClient

```ruby
# Novo método em app/services/music_generator/mureka_client.rb
def generate_soundtrack(file_id:, input_type:, prompt:, n: 2)
  post("/v1/soundtrack/generate", {
    input_type => file_id,   # "image_id" ou "video_id"
    prompt: prompt,
    model: "auto",
    n: n
  })
end
```

### B.4 Decisão de fluxo no Order model

```ruby
# Order model — após Stripe webhook confirmar pagamento:
def start_generation_pipeline!
  if tier == "pro" && soundtrack_input.present?
    UploadSoundtrackInputToMurekaJob.perform_later(id)
  else
    GenerateLyricsJob.perform_later(id)
  end
end
```

---

## C. Voice cloning — feature Pro

> **LEGADO, nunca implementado.** Não existe model `VoiceUpload` nem controller de upload de voz, e a seção 21 proíbe a funcionalidade (GDPR/AI Act). Texto original preservado como registro.

Cliente Pro pode enviar gravação da própria voz. A música final usa essa voz em vez de uma do catálogo.

### C.1 Schema

```ruby
create_table :voice_uploads do |t|
  t.references :order, foreign_key: true, null: false
  t.string :storage_key, null: false      # R2 privado
  t.string :mureka_file_id               # retornado pelo POST /v1/files/upload com purpose: "voice"
  t.string :status                        # "pending" | "processing" | "ready" | "failed"
  t.boolean :consent_given, null: false, default: false
  t.datetime :consent_given_at
  t.string :consent_ip
  t.datetime :scheduled_deletion_at      # GDPR — 30 dias após entrega
  t.datetime :deleted_at
  t.timestamps
end
```

### C.2 Regras GDPR obrigatórias

- Checkbox de consentimento explícito, não pré-marcado, com linguagem clara
- `consent_given_at` e `consent_ip` gravados no DB
- Deleção automática do arquivo R2 e do registro Mureka 30 dias após entrega
- Job `DeleteVoiceUploadJob` agendado no momento do upload

### C.3 Job

```ruby
class UploadVoiceToMurekaJob < ApplicationJob
  def perform(voice_upload_id)
    upload = VoiceUpload.find(voice_upload_id)
    # download do R2 → POST /v1/files/upload com purpose: "voice"
    # salva mureka_file_id → usado como vocal_id no MusicGenerator
  end
end
```
5. Schema do banco de dados
Migration 1: Users (Devise)
rubycreate_table :users do |t|
  # Devise core
  t.string :email, null: false, default: ""
  t.string :encrypted_password, null: false, default: ""
  t.string :reset_password_token
  t.datetime :reset_password_sent_at
  t.datetime :remember_created_at
  t.string :confirmation_token
  t.datetime :confirmed_at
  t.datetime :confirmation_sent_at
  t.string :unconfirmed_email
  t.integer :sign_in_count, default: 0, null: false
  t.datetime :current_sign_in_at
  t.datetime :last_sign_in_at
  t.string :current_sign_in_ip
  t.string :last_sign_in_ip

  # Negócio
  t.string :name
  t.string :locale, default: "it", null: false
  t.string :stripe_customer_id
  t.string :origin_brand                   # "b2b" | "b2c"
  t.string :role, default: "customer"      # "customer" | "admin" | "support"
  t.boolean :guest, default: false         # criado automaticamente no checkout B2C

  t.timestamps null: false
end

add_index :users, :email, unique: true
add_index :users, :reset_password_token, unique: true
add_index :users, :confirmation_token, unique: true
add_index :users, :stripe_customer_id
add_index :users, :origin_brand
Migration 2: Voices (catálogo curado)
rubycreate_table :voices do |t|
  t.string :provider, null: false              # "mureka"
  t.string :external_id                        # ID da voz na Mureka (opcional — algumas vozes são descritas só via prompt)
  t.string :mureka_prompt                      # ex: "pop, female vocal, warm, emotional, italian" — vai no payload da Mureka
  t.string :name, null: false
  t.string :slug, null: false
  t.text :description

  t.string :gender                             # "male" | "female" | "neutral"
  t.string :language_tags, array: true, default: []
  t.string :style_tags, array: true, default: []
  t.string :mood_tags, array: true, default: []

  t.string :sample_audio_url
  t.string :avatar_url

  t.integer :min_tier, default: 0              # 0 = standard, 1 = pro only
  t.string :allowed_brands, array: true, default: ["b2b", "b2c"]

  t.integer :display_order, default: 0
  t.boolean :active, default: true, null: false

  t.timestamps
end

add_index :voices, [:provider, :external_id], unique: true   # PG permite múltiplos NULLs em unique index
add_index :voices, :slug, unique: true
add_index :voices, :active
add_index :voices, :display_order

# Regra de modelo (Seção 3): voice deve ter pelo menos um entre external_id OU mureka_prompt
# (validado no model, não no schema, para permitir migração futura sem rebuild)
Migration 3: Orders
rubycreate_table :orders do |t|
  t.references :user, foreign_key: true, null: true

  t.string :reference, null: false             # "ORD-2026-A8F3K"
  t.string :brand, null: false                 # "b2b" | "b2c"
  t.string :locale, default: "it", null: false

  t.string :status, null: false, default: "pending"

  t.string :tier, null: false                  # "standard" | "pro" | "starter"
  t.integer :price_cents, null: false
  t.string :currency, default: "EUR", null: false

  t.integer :lyrics_regen_limit, null: false, default: 3
  t.integer :lyrics_regen_used, default: 0, null: false
  t.integer :music_regen_limit, null: false, default: 2
  t.integer :music_regen_used, default: 0, null: false

  t.string :stripe_session_id
  t.string :stripe_payment_intent_id
  t.string :stripe_charge_id
  t.datetime :paid_at

  t.references :approved_lyrics_draft, foreign_key: { to_table: :lyrics_drafts }, null: true
  t.references :approved_music_generation, foreign_key: { to_table: :music_generations }, null: true
  t.string :approved_variant                   # "a" | "b"
  t.datetime :approved_at

  t.string :delivery_email, null: false
  t.datetime :delivered_at
  t.datetime :first_download_at
  t.integer :download_count, default: 0

  t.text :internal_notes
  t.datetime :cancelled_at
  t.string :cancellation_reason

  t.timestamps
end

add_index :orders, :reference, unique: true
add_index :orders, [:brand, :status]
add_index :orders, :stripe_session_id
add_index :orders, :stripe_payment_intent_id
add_index :orders, :created_at
add_index :orders, :paid_at
Migration 4: Briefings
rubycreate_table :briefings do |t|
  t.references :order, foreign_key: true, null: false
  t.references :voice, foreign_key: true, null: true

  t.string :title
  t.text :about, null: false
  t.string :recipient
  t.string :occasion
  t.text :keywords
  t.text :avoid

  t.string :music_style, null: false
  t.string :mood
  t.string :tempo
  t.integer :target_duration_seconds, default: 120
  t.string :language, default: "it", null: false

  t.jsonb :extra_params, default: {}

  t.timestamps
end

add_index :briefings, :order_id, unique: true
add_index :briefings, :music_style
add_index :briefings, :occasion
Migration 5: Lyrics Drafts
rubycreate_table :lyrics_drafts do |t|
  t.references :order, foreign_key: true, null: false

  t.integer :version, null: false
  t.string :source, null: false                # "ai_generated" | "user_edited" | "regenerated"

  t.text :content, null: false                 # texto corrido formatado (fonte de verdade exposta ao usuário)
  t.jsonb :structure, default: {}              # JSON estruturado (verse_1, chorus, ...) — INTERNO: usado para montar prompt da Mureka, nunca exposto na UI

  t.text :user_feedback
  t.references :parent_draft, foreign_key: { to_table: :lyrics_drafts }, null: true

  t.string :llm_provider                       # "anthropic"
  t.string :llm_model                          # "claude-opus-4-7"
  t.string :prompt_version
  t.integer :input_tokens
  t.integer :output_tokens
  t.integer :latency_ms

  t.boolean :is_approved, default: false, null: false
  t.datetime :approved_at
  t.boolean :is_locked, default: false, null: false

  t.timestamps
end

add_index :lyrics_drafts, [:order_id, :version], unique: true
add_index :lyrics_drafts, [:order_id, :is_approved]
Migration 6: Music Generations
rubycreate_table :music_generations do |t|
  t.references :order, foreign_key: true, null: false
  t.references :voice, foreign_key: true, null: false
  t.references :lyrics_draft, foreign_key: true, null: false

  t.integer :iteration, null: false            # 1 = inicial, 2 = primeira regen...

  t.string :provider, null: false              # "mureka"
  t.string :provider_task_id
  t.string :provider_model

  t.string :status, null: false, default: "pending"

  t.string :music_style, null: false
  t.string :mood
  t.string :tempo
  t.integer :target_duration_seconds

  t.text :user_feedback
  t.string :feedback_type
  t.references :parent_generation, foreign_key: { to_table: :music_generations }, null: true

  t.jsonb :request_payload, default: {}
  t.jsonb :response_payload, default: {}

  t.string :variant_a_provider_song_id
  t.string :variant_a_full_url
  t.string :variant_a_preview_url
  t.string :variant_a_stems_url
  t.integer :variant_a_duration_ms

  t.string :variant_b_provider_song_id
  t.string :variant_b_full_url
  t.string :variant_b_preview_url
  t.string :variant_b_stems_url
  t.integer :variant_b_duration_ms

  t.text :error_message
  t.string :error_code
  t.integer :attempt_count, default: 0

  t.datetime :submitted_at
  t.datetime :ready_at
  t.integer :total_latency_ms

  t.timestamps
end

add_index :music_generations, [:order_id, :iteration], unique: true
add_index :music_generations, :provider_task_id
add_index :music_generations, :status
Migration 7: Generation Jobs (log de chamadas LLM)
rubycreate_table :generation_jobs do |t|
  t.references :order, foreign_key: true, null: false
  t.references :lyrics_draft, foreign_key: true, null: true

  t.string :provider, null: false              # "anthropic"
  t.string :model, null: false
  t.string :step, null: false                  # "lyrics_initial" | "lyrics_regen" | "lyrics_refine"
  t.string :status, default: "pending"

  t.string :prompt_version
  t.jsonb :request_payload, default: {}
  t.jsonb :response_payload, default: {}

  t.integer :input_tokens
  t.integer :output_tokens
  t.integer :total_tokens
  t.decimal :cost_usd, precision: 10, scale: 6

  t.text :error_message
  t.string :error_code
  t.integer :attempt_count, default: 0

  t.datetime :started_at
  t.datetime :finished_at
  t.integer :latency_ms

  t.timestamps
end

add_index :generation_jobs, [:order_id, :step]
add_index :generation_jobs, :status
add_index :generation_jobs, :created_at
Migration 8: Order Assets
rubycreate_table :order_assets do |t|
  t.references :order, foreign_key: true, null: false
  t.references :music_generation, foreign_key: true, null: true

  t.string :kind, null: false                  # "final_mp3" | "final_wav" | "stems_zip" | "lyrics_pdf"
  t.string :storage_key, null: false
  t.string :url
  t.datetime :url_expires_at

  t.integer :file_size_bytes
  t.string :mime_type
  t.string :checksum_sha256

  t.integer :download_count, default: 0
  t.datetime :last_downloaded_at

  t.timestamps
end

add_index :order_assets, [:order_id, :kind]
Migration 9: Stripe Events (webhook idempotency)
rubycreate_table :stripe_events do |t|
  t.string :stripe_event_id, null: false
  t.string :event_type, null: false
  t.string :status, default: "pending"

  t.references :order, foreign_key: true, null: true

  t.jsonb :payload, null: false
  t.text :error_message
  t.integer :attempt_count, default: 0

  t.datetime :processed_at
  t.timestamps
end

add_index :stripe_events, :stripe_event_id, unique: true
add_index :stripe_events, :event_type
add_index :stripe_events, :status
Migration 10: Refund Requests
rubycreate_table :refund_requests do |t|
  t.references :order, foreign_key: true, null: false
  t.references :user, foreign_key: true, null: false

  t.string :status, default: "pending"
  t.text :reason, null: false
  t.string :reason_category

  t.string :stripe_refund_id
  t.integer :refunded_amount_cents
  t.text :resolution_notes
  t.references :resolved_by, foreign_key: { to_table: :users }, null: true
  t.datetime :resolved_at

  t.timestamps
end

add_index :refund_requests, :status
Migration 11: Email Deliveries
rubycreate_table :email_deliveries do |t|
  t.references :order, foreign_key: true, null: true
  t.references :user, foreign_key: true, null: true

  t.string :template, null: false
  t.string :recipient_email, null: false
  t.string :locale, null: false
  t.string :brand, null: false

  t.string :status, default: "queued"
  t.string :provider_message_id

  t.text :error_message
  t.datetime :sent_at
  t.datetime :opened_at
  t.datetime :clicked_at

  t.timestamps
end

add_index :email_deliveries, [:order_id, :template]
add_index :email_deliveries, :status
6. Service objects necessários
app/services/
├── brand_locale_resolver.rb          # detecta brand+locale por host
├── lyrics_generator/
│   ├── claude_client.rb              # wrapper Anthropic API
│   ├── prompt_builder.rb             # monta prompt a partir do briefing
│   └── generator.rb                  # orquestra geração + regeneração
├── music_generator/
│   ├── mureka_client.rb              # wrapper Mureka API
│   ├── generator.rb                  # orquestra geração + polling
│   └── audio_processor.rb            # FFmpeg: corta preview, normaliza
├── stripe/
│   ├── checkout_builder.rb           # cria Stripe Checkout Session
│   └── webhook_handler.rb            # processa eventos com idempotência
├── orders/
│   ├── creator.rb                    # cria Order a partir de briefing
│   ├── lyrics_approver.rb            # trava letra + dispara música
│   ├── music_approver.rb             # finaliza pedido + dispara entrega
│   └── reference_generator.rb        # gera "ORD-2026-A8F3K"
└── delivery/
    ├── asset_uploader.rb             # baixa da Mureka, faz upload S3/R2
    └── signed_url_generator.rb       # URL assinada com expiração
7. Jobs (Solid Queue)

> Corrigido o título (o projeto usa Solid Queue, não Sidekiq). A lista abaixo é do desenho original; os jobs reais da campanha estão em `app/jobs/` (`GenerateCampaignMusicJob`, `PollCampaignMusicJob`, `RecoverCampaignMusicJob`, `ArchiveCampaignAudioJob`, `PrepareCampaignAudioJob`, `RewriteCampaignLyricsJob`, `RenderCampaignVideoJob`).

app/jobs/
├── generate_lyrics_job.rb            # chama Claude, salva LyricsDraft
├── generate_music_job.rb             # chama Mureka, salva MusicGeneration
├── poll_mureka_status_job.rb         # polling se Mureka não tiver webhook
├── process_music_preview_job.rb      # FFmpeg corta preview 30s + sobe S3
├── deliver_order_job.rb              # envia email final + cria assets
└── stripe_webhook_processor_job.rb   # processa StripeEvent assíncrono
Retry policy: exponential backoff, max 5 tentativas. Após esgotar, status vai pra _failed e notifica admin via email.
8. State machine da Order (usar AASM)

> **Desatualizada em parte.** O model real tem 13 estados: não existe `delivered` nem o evento `mark_delivered`, e há eventos que o desenho não prevê (`start_soundtrack_generation` é LEGADO; `regenerate_music`, `cancel` e `refund` existem). A lista e as transições conferidas estão na seção 0.4. O mapeamento para fases do estúdio e estados da Biblioteca também.

rubyclass Order < ApplicationRecord
  include AASM

  aasm column: :status do
    state :pending, initial: true
    state :payment_failed
    state :paid
    state :lyrics_drafting
    state :lyrics_ready
    state :lyrics_failed
    state :lyrics_approved
    state :music_generating
    state :preview_ready
    state :music_failed
    state :approved
    state :delivered
    state :cancelled
    state :refunded

    event :mark_paid do
      transitions from: :pending, to: :paid
      after { GenerateLyricsJob.perform_later(id) }
    end

    event :start_lyrics_generation do
      transitions from: :paid, to: :lyrics_drafting
    end

    event :lyrics_drafted do
      transitions from: :lyrics_drafting, to: :lyrics_ready
      after { OrderMailer.lyrics_ready(self).deliver_later }
    end

    event :approve_lyrics do
      transitions from: :lyrics_ready, to: :lyrics_approved,
                  guard: :has_unapproved_lyrics_draft?
      after :lock_lyrics_and_start_music
    end

    event :start_music_generation do
      transitions from: :lyrics_approved, to: :music_generating
    end

    event :music_ready do
      transitions from: :music_generating, to: :preview_ready
      after { OrderMailer.preview_ready(self).deliver_later }
    end

    event :approve_music do
      transitions from: :preview_ready, to: :approved
      after { DeliverOrderJob.perform_later(id) }
    end

    event :mark_delivered do
      transitions from: :approved, to: :delivered
      after { OrderMailer.delivered(self).deliver_later }
    end

    event :fail_lyrics, after: :notify_admin do
      transitions from: [:lyrics_drafting], to: :lyrics_failed
    end

    event :fail_music, after: :notify_admin do
      transitions from: [:music_generating], to: :music_failed
    end
  end
end
9. Fluxo Stripe completo
Criação do Checkout

Cliente preenche briefing e escolhe tier
Order é criada com status: :pending, Briefing associada
Backend cria Stripe::Checkout::Session com success_url e cancel_url apontando pra order
Cliente redirecionado pro Stripe Checkout

Webhook handling

Stripe envia webhook pra /stripe/webhook
Verifica assinatura HMAC
Cria/recupera StripeEvent (idempotência por stripe_event_id)
Se já processado, retorna 200 e ignora
Se novo, enfileira StripeWebhookProcessorJob
Job processa por tipo:

checkout.session.completed → order.mark_paid!
payment_intent.payment_failed → order.update(status: :payment_failed)
charge.refunded → cria/atualiza RefundRequest



Importante: webhook handler retorna 200 SEMPRE que assinatura é válida, processamento é assíncrono. Senão Stripe vai retry e cria duplicação.
10. Páginas/telas a implementar

> **Desatualizada em parte.** As telas e rotas atuais da campanha estão na seção 0.6. `/orders/new` hoje só redireciona (cadastro ou `/campaigns/new`); o **wizard de 5 passos é LEGADO** (`/orders/wizard/:step`). `/pricing`, `/exemplos`, `/faq`, `/terms`, `/privacy`, `/dashboard`, `/account` e `/admin/*` não existem nas rotas atuais (a Biblioteca é `/songs`; o FAQ e o preço ficam na landing).

Públicas (sem auth)

/ → Landing por brand (B2B ou B2C, conforme host)
/pricing → Detalhes dos tiers
/exemplos → Galeria de exemplos
/faq, /terms, /privacy
/orders/new → Wizard de briefing (multi-step com Turbo Frames)

Autenticadas

/orders/:id → Status da order (varia por estado)
/orders/:id/lyrics → Revisão de letra (NÃO é editor inline — ver seção 10.1)
/orders/:id/preview → Player das 2 variantes A/B
/orders/:id/download → Página de download final
/dashboard → Lista de orders do usuário
/account → Configurações do user

Admin

/admin/orders → Painel de orders
/admin/voices → CRUD de catálogo
/admin/refund_requests → Gestão de refunds
Usar administrate gem ou montar manual com Pundit

10.1 UI de revisão de letra (princípio: simplicidade radical)

O usuário NÃO vê a estrutura musical (verso/refrão/bridge). A estrutura JSON existe só no banco e no prompt da Mureka — nunca exposta na UI.

A página exibe:
- Letra como texto corrido, formatada como poema (preserva quebras de linha)
- Dois botões grandes:
  - "Está perfeita ✓" → aprova letra, dispara geração de música (trava o draft via lyrics_approved)
  - "Quero ajustar" → abre um campo de texto livre: "O que você gostaria de mudar?"
- Contador discreto no topo ou rodapé: "Você tem X ajustes disponíveis"
  - X = order.lyrics_regen_limit - order.lyrics_regen_used

Quando o usuário envia feedback no "Quero ajustar":
- Cria nova LyricsDraft com source: "regenerated", parent_draft apontando para a versão anterior
- Incrementa order.lyrics_regen_used
- Enfileira GenerateLyricsJob (regen, ver seção 13.2)
- Turbo Stream substitui a letra renderizada quando o job terminar

Quando esgotar regenerações:
- Botão "Quero ajustar" desabilitado com tooltip "Limite de ajustes atingido"
- Mantém apenas "Está perfeita ✓"

NÃO IMPLEMENTAR:
- Blocos editáveis por seção (verso, refrão, etc.)
- Botão "regenerar este bloco"
- Editor inline de texto da letra
- Qualquer menção a estrutura musical na interface
- Visualização da JSON estruturada

11. I18n
Estrutura:
config/locales/
├── it.yml                # base italiana (mercado principal)
├── en.yml
├── es.yml
├── fr.yml
├── de.yml
├── pt.yml
└── brands/
    ├── b2b/
    │   ├── it.yml        # textos específicos do B2B em italiano
    │   ├── en.yml
    │   └── ...
    └── b2c/
        ├── it.yml
        ├── en.yml
        └── ...
Helper pra resolver chaves por brand:
rubydef t_brand(key, **opts)
  t("brands.#{@brand}.#{key}", **opts, default: t(key, **opts))
end
12. Mureka API — integração
Importante: assumir que a Mureka tem endpoint de geração assíncrono com polling. Confirmar na doc oficial em https://platform.mureka.ai/docs
Fluxo esperado:

POST /v1/song/generate com { lyrics, voice_id, style, mood, duration }
Resposta imediata: { task_id, status: "pending" }
Polling GET /v1/song/query?task_id=... a cada 10s até status: "completed"
Resposta final: URLs das 2 variantes (song_url_a, song_url_b)
Download dos MP3s, upload pro S3/R2, geração de previews com FFmpeg

Webhook se disponível: preferir webhook a polling. Endpoint /webhooks/mureka recebe notificação.
Catálogo de vozes: buscar via API ou popular manualmente no banco com seed (db/seeds/voices.rb).
13. Geração de letra — pipeline dupla

13.1 Geração inicial (Mureka → Claude)

⚠️ DECISÃO PENDENTE: confirmar se POST /v1/lyrics/generate (Mureka) desconta créditos do plano $30/mês ou é incluso. Verificar na doc oficial https://platform.mureka.ai/docs antes de implementar a Seção 9.
- Se for incluso: usar pipeline dupla (Mureka → Claude).
- Se cobrar por chamada: PULAR etapa 1 e ir direto pro Claude com o prompt de geração inicial.

Pipeline (assumindo Mureka inclusa):

Etapa 1 — Mureka gera rascunho bruto:
  POST /v1/lyrics/generate com prompt resumido do briefing
  Input: "{{music_style}} song in {{language}} about {{about}} for {{recipient}} on {{occasion}}"
  Output: texto bruto de letra (sem estrutura formal garantida)

Etapa 2 — Claude refina e estrutura:
  Input: rascunho da Mureka + briefing completo
  Claude:
  - Estrutura em JSON (verse_1, chorus, verse_2, bridge, chorus_final)
  - Garante idioma correto (não traduz, escreve naturalmente em {{language}})
  - Incorpora keywords obrigatórios
  - Remove temas a evitar
  - Ajusta tom/estilo conforme briefing
  Output: JSON estruturado

Etapa 3 — Persistência:
  - lyrics_drafts.content = texto corrido formatado (extraído do JSON, com quebras de linha entre seções)
  - lyrics_drafts.structure = JSON estruturado (interno, nunca exposto na UI — ver seção 10.1)
  - lyrics_drafts.source = "ai_generated"
  - lyrics_drafts.version = 1
  - Log em generation_jobs (provider: "mureka" + "anthropic", uma row pra cada chamada)

Prompt do Claude (etapa 2, refino):

rubyREFINE_PROMPT = <<~PROMPT
  You are a professional songwriter specialized in {{music_style}} music in {{language}}.

  Below is a raw draft generated by another AI. Your job is to refine and structure it.

  RAW DRAFT:
  {{mureka_raw_draft}}

  BRIEFING (must be respected):
  - Style: {{music_style}}
  - Mood: {{mood}}
  - Language: {{language}} (write naturally, do not translate)
  - Recipient/context: {{recipient}} for {{occasion}}
  - Must include: {{keywords}}
  - Avoid: {{avoid}}
  - Target duration: ~{{target_duration}}s when sung (verse ~30s, chorus ~20s)

  Restructure the draft into proper song sections, fix any language/style inconsistencies,
  ensure keywords are present, and remove any avoided themes.

  Output STRICTLY as JSON:
  {
    "verse_1": "...",
    "chorus": "...",
    "verse_2": "...",
    "bridge": "...",
    "chorus_final": "..."
  }

  Do not include any explanation, only the JSON.
PROMPT

Se Mureka cobra por chamada (decisão pendente acima), usar este prompt direto com o briefing no lugar de RAW DRAFT, removendo a etapa Mureka.

13.2 Regeneração (Claude apenas, sempre)

Quando o usuário pede ajuste via "Quero ajustar" (seção 10.1), só Claude é chamado — Mureka não participa da regen, pois temos a letra base e o feedback livre é mais bem interpretado por LLM.

Prompt:

rubyREGEN_PROMPT = <<~PROMPT
  CURRENT LYRICS:
  {{current_lyrics_full_text}}

  USER FEEDBACK:
  "{{user_feedback}}"

  BRIEFING (never forget):
  - Style: {{music_style}}
  - Mood: {{mood}}
  - Language: {{language}}
  - Must include: {{keywords}}
  - Avoid: {{avoid}}

  Rewrite incorporating the feedback naturally.
  Keep what's working, change what the user asked.
  Output STRICTLY as JSON: { verse_1, chorus, verse_2, bridge, chorus_final }
PROMPT

13.3 Versionamento de prompts

Cada mudança em qualquer prompt (REFINE, REGEN, ou geração direta) incrementa prompt_version ("v1.0", "v1.1") e fica registrado em LyricsDraft.prompt_version pra A/B testing futuro.
14. FFmpeg — processamento de preview
bash# Corta primeiros 30s + fade-out 3s
ffmpeg -y -i input.mp3 \
  -t 30 \
  -af "afade=t=out:st=27:d=3" \
  -codec:a libmp3lame -b:a 128k \
  output_preview.mp3
Roda dentro de ProcessMusicPreviewJob. Tempfile no /tmp, upload pro bucket público após sucesso.
15. Storage — buckets separados

Bucket público (music-previews-public): previews 30s, samples de vozes, avatars. URLs diretas.
Bucket privado (music-finals-private): MP3 completos, WAV, stems. URLs assinadas com expiração de 1h, regeradas sob demanda.

Cliente nunca recebe URL direta do bucket privado. Sempre via endpoint Rails /orders/:id/download/:asset_id que valida ownership e gera signed URL.
16. Emails transacionais
Templates necessários (todos em todos os idiomas):

order_confirmation — após pagamento
lyrics_ready — letra pronta pra revisar
preview_ready — música pronta pra escolher variante
order_delivered — link de download
refund_processed — refund aprovado
order_failed — algo deu errado, ação manual

Usar ActionMailer com layouts por brand:
app/views/order_mailer/
├── b2b/
│   ├── lyrics_ready.html.erb
│   └── ...
└── b2c/
    ├── lyrics_ready.html.erb
    └── ...
17. Variáveis de ambiente necessárias
bash# Rails
RAILS_MASTER_KEY=
DATABASE_URL=
REDIS_URL=

# Stripe
STRIPE_PUBLISHABLE_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=

# Anthropic
ANTHROPIC_API_KEY=

# Mureka
MUREKA_API_KEY=
MUREKA_WEBHOOK_SECRET=    # se webhook disponível

# Storage (Cloudflare R2)
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_ENDPOINT=
R2_BUCKET_PUBLIC=
R2_BUCKET_PRIVATE=

# Email
POSTMARK_API_TOKEN=    # ou RESEND_API_KEY

# Sentry
SENTRY_DSN=
18. Configuração por brand (YAML)

> **LEGADO / desatualizado.** O `config/brands.yml` real só tem a chave `b2b` (sem `b2c`), com `default_locale: pt`, `currency: BRL`, `campaign_tier: starter` e os tiers `starter` (R$ 79; `lyrics_regen_limit: 20`, `music_regen_limit: 2`) e `pro` (legado). O bloco abaixo é o desenho original.
yaml# config/brands.yml
b2b:
  hosts: ["jinglepro.it", "jinglepro.com"]
  display_name: "JinglePro"   # placeholder, ajustar com nome final
  default_locale: it
  supported_locales: [it, en, es, fr, de]
  primary_color: "#1a3a5c"
  tiers:
    starter:
      price_cents: 7900
      lyrics_regen_limit: 2
      music_regen_limit: 1
      includes_stems: false
      max_duration_seconds: 60
    pro:
      price_cents: 14900
      lyrics_regen_limit: 3
      music_regen_limit: 2
      includes_stems: true
      max_duration_seconds: 90

b2c:
  hosts: ["musicaregalo.it", "musicaregalo.com"]
  display_name: "MusicaRegalo"   # placeholder
  default_locale: it
  supported_locales: [it, en, es, fr, de, pt]
  primary_color: "#e85d75"
  tiers:
    standard:
      price_cents: 1900
      lyrics_regen_limit: 2
      music_regen_limit: 1
      includes_stems: false
      max_duration_seconds: 120
    pro:
      price_cents: 3900
      lyrics_regen_limit: 3
      music_regen_limit: 2
      includes_stems: true
      max_duration_seconds: 180
19. Ordem de implementação sugerida

[x] Setup base: Rails 8 novo, PostgreSQL, Solid Queue, Devise, Tailwind, Hotwire
[x] Schema: rodar todas as 11 migrations
[x] Models + associations + validations (sem state machine ainda)
[x] AASM na Order com todas transições
[x] Brand/Locale resolver + multi-host setup
Seed do catálogo de vozes (placeholder até integrar Mureka)
Wizard de briefing (multi-step com Turbo Frames)
Stripe Checkout + webhook handler
LyricsGenerator service + Claude integration + job
Editor de letra (Stimulus + Turbo Streams pra regen)
MurekaClient + integration + polling/webhook
AudioProcessor com FFmpeg
Preview/approval flow (player + variantes A/B)
Delivery flow (signed URLs + download)
Email templates (todos brands × locales)
Admin panel (Administrate)
Landing pages (B2B e B2C)
Testes (Minitest, fixtures, system tests com Capybara)

20. Testes esperados

Unit: todos os service objects, especialmente clients (Claude, Mureka, Stripe) com WebMock
Integration: jobs Solid Queue, webhook handlers
System: fluxo completo de pedido (briefing → checkout fake → letra → música mockada → download)
State machine: todas transições válidas e inválidas

21. Importante

Não implementar voice cloning (clonagem de voz do usuário). Fora do MVP por motivos GDPR/AI Act.
Não implementar assinatura recorrente. One-shot por pedido.
Não implementar app nativo agora. Arquitetura suporta no futuro.
Não implementar SSO/OAuth. Email+senha via Devise apenas.
Não implementar marketplace de músicas geradas.
Todos os preços e textos devem ser facilmente configuráveis (YAML + I18n), pra permitir testes A/B.
