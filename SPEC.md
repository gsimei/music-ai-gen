Spec Técnico — Plataforma de Geração de Música com AI
1. Visão geral
Plataforma web (Rails 8 + Hotwire) que permite a usuários encomendar músicas personalizadas geradas com AI. Cliente preenche briefing, paga via Stripe, revisa letra gerada por LLM, aprova e recebe duas variantes de música pra escolher, e baixa o arquivo final.
Duas marcas independentes sob o mesmo backend:

B2B (jingles para pequenos negócios) — ticket €79-149
B2C (música como presente) — ticket €19-39

Mercado: Europa, com Itália como mercado principal. Multi-idioma desde o início (it, en, es, fr, de, pt).
Arquitetura: Rails 8 monolito + Hotwire + Tailwind. Sem SPA, sem frontend separado. Preparado pra futuro app Hotwire Native (não desenvolver agora).
2. Stack técnica

Backend: Ruby on Rails 8, PostgreSQL 16+
Frontend: Hotwire (Turbo + Stimulus), Tailwind CSS 4
Auth: Devise + Pundit
Background jobs: Solid Queue
Pagamento: Stripe Checkout (não usar Stripe Elements customizado) + webhooks
Storage: ActiveStorage com S3-compatible (Cloudflare R2 recomendado pra economizar bandwidth)
Email: Postmark ou Resend (transacional)
Processamento áudio: FFmpeg (server-side, via shell)
AI providers:

Letras: Anthropic Claude (modelo claude-opus-4-7)
Música: Mureka API oficial (platform.mureka.ai), tier inicial $30/mês 1 concurrent


Deploy: Kamal (mesmo padrão do Lare)
Monitoring: Sentry (errors) + Mission Control Jobs (Sidekiq dashboard)

3. Modelo de negócio
Tiers e preços por marca
yamlB2C (musicaregalo.it / .com / .es / .fr / etc.):
  standard: €19
    - MP3 final
    - 2 regenerações de letra
    - 1 regeneração de música
    - Vozes do catálogo standard
  pro: €39
    - MP3 + WAV + stems separados
    - 3 regenerações de letra
    - 2 regenerações de música
    - Vozes premium
    - PDF estilizado da letra

B2B (jinglepro.it / .com / .es / etc.):
  starter: €79
    - Jingle 30-60s, MP3
    - 2 regenerações de letra
    - 1 regeneração de música
    - Uso comercial incluído
  pro: €149
    - Jingle 60-90s, MP3 + WAV + stems
    - 3 regenerações de letra
    - 2 regenerações de música
    - 2 versões finais entregues
    - Uso comercial + fatura formal
Preços e limites devem ser configuráveis via YAML, NÃO hardcoded. Cada pedido cacheia os limites no DB no momento da compra.
Fluxo do cliente (10 estados)
1. pending           → cliente preencheu briefing, ainda não pagou
2. paid              → Stripe webhook confirmou pagamento
3. lyrics_drafting   → LLM gerando primeira versão da letra
4. lyrics_ready      → letra disponível pra cliente revisar
5. lyrics_approved   → cliente aprovou letra (FICA TRAVADA daqui em diante)
6. music_generating  → Mureka gerando música (2 variantes)
7. preview_ready     → cliente pode ouvir os 2 previews (30s cada)
8. approved          → cliente escolheu uma variante e aprovou
9. delivered         → arquivo final disponível pra download

Estados de falha: payment_failed, lyrics_failed, music_failed, cancelled, refunded
4. Modelo de domínios
Estratégia: domínios localizados pra Itália (mercado principal) + .com pra demais idiomas
B2C:
- musicaregalo.it    → b2c, locale it (forçado)
- musicaregalo.com   → b2c, locale detectado por Accept-Language ou /locale path

B2B:
- jinglepro.it       → b2b, locale it (forçado)
- jinglepro.com      → b2b, locale detectado por Accept-Language ou /locale path
Nota: os nomes acima são placeholders, o usuário ainda vai escolher o nome final. Estruturar config pra ser facilmente trocável.
Rails detecta host na requisição, seta @brand (b2b/b2c) e I18n.locale via before_action. Routes usam constraints por host.
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
  t.string :external_id, null: false           # ID da voz na Mureka
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

add_index :voices, [:provider, :external_id], unique: true
add_index :voices, :slug, unique: true
add_index :voices, :active
add_index :voices, :display_order
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

  t.text :content, null: false
  t.jsonb :structure, default: {}

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
7. Sidekiq jobs
app/jobs/
├── generate_lyrics_job.rb            # chama Claude, salva LyricsDraft
├── generate_music_job.rb             # chama Mureka, salva MusicGeneration
├── poll_mureka_status_job.rb         # polling se Mureka não tiver webhook
├── process_music_preview_job.rb      # FFmpeg corta preview 30s + sobe S3
├── deliver_order_job.rb              # envia email final + cria assets
└── stripe_webhook_processor_job.rb   # processa StripeEvent assíncrono
Retry policy: exponential backoff, max 5 tentativas. Após esgotar, status vai pra _failed e notifica admin via email.
8. State machine da Order (usar AASM)
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
Públicas (sem auth)

/ → Landing por brand (B2B ou B2C, conforme host)
/pricing → Detalhes dos tiers
/exemplos → Galeria de exemplos
/faq, /terms, /privacy
/orders/new → Wizard de briefing (multi-step com Turbo Frames)

Autenticadas

/orders/:id → Status da order (varia por estado)
/orders/:id/lyrics → Editor de letra (Stimulus controller pra edição inline)
/orders/:id/preview → Player das 2 variantes A/B
/orders/:id/download → Página de download final
/dashboard → Lista de orders do usuário
/account → Configurações do user

Admin

/admin/orders → Painel de orders
/admin/voices → CRUD de catálogo
/admin/refund_requests → Gestão de refunds
Usar administrate gem ou montar manual com Pundit

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
13. Prompt do Claude pra letra
rubySYSTEM_PROMPT = <<~PROMPT
  You are a professional songwriter specialized in {{music_style}} music in {{language}}.

  Generate song lyrics that:
  - Are structured with sections: [verse 1], [chorus], [verse 2], [bridge], [chorus]
  - Match the style "{{music_style}}" with appropriate meter and rhyme
  - Convey the mood "{{mood}}"
  - Are roughly {{target_duration}} seconds when sung (verse ~30s, chorus ~20s)
  - Are written in {{language}} naturally, not translated

  Constraints:
  - Always include these keywords or facts: {{keywords}}
  - Never use these words or themes: {{avoid}}
  - Recipient/context: {{recipient}} for {{occasion}}

  Output STRICTLY as JSON:
  {
    "structure": {
      "verse_1": "...",
      "chorus": "...",
      "verse_2": "...",
      "bridge": "...",
      "chorus_final": "..."
    },
    "full_text": "complete formatted lyrics with line breaks"
  }

  Do not include any explanation, only the JSON.
PROMPT
Versioning: cada mudança no prompt incrementa prompt_version ("v1.0", "v1.1") e fica registrado em LyricsDraft.prompt_version pra A/B testing futuro.
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

Setup base: Rails 8 novo, PostgreSQL, Sidekiq, Devise, Tailwind, Hotwire
Schema: rodar todas as 11 migrations
Models + associations + validations (sem state machine ainda)
AASM na Order com todas transições
Brand/Locale resolver + multi-host setup
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
