# Music AI Gen — Instruções para o Claude

Produto único: a **Campanha** da **ViraJingle**. O lojista informa a oferta do negócio e envia até 5 fotos iniciais (ampliáveis no estúdio conforme a duração, até 30; `Campaigns::PhotoLimit`), paga uma vez via Stripe Checkout, revisa e edita a letra, escolhe entre 2 músicas por rodada (até 3 rodadas, limite em `Campaigns::MusicRounds::LIMIT`) e recebe vídeo vertical 9:16 (MP4) + música em MP3 + legenda sugerida.

Mercado: Brasil. Interface em português (pt-BR) e preço em BRL: R$ 29,90 por campanha, pagamento único, sem assinatura. O valor vem de `config/brands.yml` (`campaign_tier` → `tiers.starter.price_cents`) e do helper `campaign_price` — **nunca hardcoded**.

Não existem mais duas marcas (B2B/B2C), preços em € nem mercado europeu multi-idioma. O código ainda carrega vestígios disso (ver "Marca e locale" abaixo); não os reative sem passar pelo `idea-validator`.

Funcionalidades **LEGADO** (fora do produto; o código ainda está no repositório e a remoção está planejada na fatia 5 do redesign, ver ROADMAP): chat conversacional (`OrderChat`, `ConversationalReplyJob`, `BriefingMessage`), soundtrack (`SoundtrackInput`) e wizard de 5 passos (`orders#wizard_*`). Voice cloning também é LEGADO, mas só existe no SPEC (nunca foi implementado). Não construa nada novo em cima delas. Atenção: hoje o estúdio da campanha ainda é renderizado dentro de `order_chat/` (rota `/orders/:id/chat`); isso muda na fatia 3.

---

## Stack

Conferida em `Gemfile`, `Gemfile.lock`, `config/`, `Dockerfile` e `layouts/application.html.erb`.

| Camada | Tecnologia |
|---|---|
| Linguagem | Ruby 4.0.5 (`.ruby-version`) |
| Framework | Rails 8.1 (8.1.4.1 no lock) |
| Banco de dados | PostgreSQL (versão a confirmar) |
| Frontend | Hotwire (Turbo + Stimulus) via importmap-rails; assets via Propshaft |
| CSS | `stylesheet_link_tag :app` carrega em **todas** as páginas tudo o que está em `app/assets/**/*.css` (glob do Propshaft): CSS escrito à mão em `app/assets/stylesheets/` (`landing.css`, `studio.css`, `studio_app.css`, `studio_identity.css`) + Tailwind CSS 4 (`tailwindcss-rails`, entrada em `app/assets/tailwind/application.css`, classes utilitárias ainda aparecem em views de `lyrics/`, `order_chat/`, `orders/`, `music_preview/` e `pages/`). A fatia 1 do redesign unifica o CSS |
| Movimento | `app/javascript/jp_motion.js` e `jp_waveform.js`; GSAP 3.12.5 carregado por CDN (cdnjs) no layout e usado como melhoria opcional em `jp_motion.js` |
| Fontes | Manrope e Cormorant Garamond (Google Fonts, no layout) |
| Auth | Devise 5 + Pundit |
| Background jobs | Solid Queue em produção (banco `queue`); `:async` em development |
| Cache / Cable | Solid Cache e Solid Cable (Gemfile) |
| Pagamento | Stripe Checkout + webhooks (gem `stripe` 13) |
| Storage | ActiveStorage com serviço Disk (`config/storage.yml` só tem `local` e `test`). Cloudflare R2 é planejado (ROADMAP, M-4), não configurado |
| Email | Mailers do Devise e ApplicationMailer; Resend via SMTP/TLS em produção, configurada por `RESEND_API_KEY`, `MAILER_FROM` e `APP_HOST` (sem gem extra). Conta, domínio verificado e teste de entrega ainda precisam ser ativados |
| Áudio e vídeo | FFmpeg/ffprobe e ImageMagick no servidor (instalados no `Dockerfile`); vídeo MP4 720x1280, H.264 + AAC, duração ajustável até a música inteira (padrão 30 s) |
| AI — Letras | Mureka `POST /v1/lyrics/generate` (`LyricsGenerator::MurekaLyricsClient`), na geração inicial e na reescrita |
| AI — Música | Mureka `POST /v1/song/generate`, modelo `mureka-9`, `n: 2` (`Campaigns::MusicRounds::MODEL`) |
| AI — Chat (LEGADO) | `ConversationalBriefingService` via `LyricsGenerator::ClaudeClient`, que chama a OpenAI `gpt-4o-mini` (gem `ruby-openai`, `OPENAI_API_KEY`). O nome da classe é herdado: não há Anthropic no Gemfile |
| Deploy | Kamal 2 (Docker) |
| Monitoramento | Sentry (`sentry-rails`, DSN via `SENTRY_DSN`) |

---

## Comandos essenciais

```bash
bin/dev                          # foreman: web (porta 3000) + tailwindcss:watch + Stripe CLI (Procfile.dev)
bin/rails test                   # suite completa de testes
bin/rails test test/models/      # testes por categoria
bin/rails db:migrate             # roda migrations pendentes
bin/rails campaigns:costs        # CSV de custo estimado de API por campanha (CAMPAIGN_ID opcional)
kamal deploy                     # deploy de nova versão
```

O processo `stripe` do `bin/dev` exige o Stripe CLI instalado e `STRIPE_SECRET_KEY` no ambiente; ele encaminha o webhook para `b2b.lvh.me:3000/stripe/webhook`. O renderizador de vídeo precisa de FFmpeg/ffprobe e ImageMagick locais.

---

## Referência de design

O design de referência para o frontend está em `design/jinglepro/`, exportado de um canvas de design em 09/11/2026. Ele substitui o antigo `Plataforma - Vanilla.html` e o protótipo `jinglepro/` de maio/2026 (`JinglePro.html`, `jp-styles.css`). Os dois foram removidos e continuam recuperáveis pelo commit `738df98` (baseline).

Conteúdo da pasta:
- `*.dc.html`: uma prancha por tela (`Main`, `Landing-Mobile`, `Entrar`, `Criar`, `Criar-Mobile`, `Estudio`, `Estudio-Mobile`, `Entrega`, `Biblioteca`, `Estados`, `Diagnostico`)
- `canvas.json`: posição e tamanho de cada prancha no canvas
- `README.md`: **leia primeiro.** Mapa prancha → tela do app → fatia do redesign, tokens (`--jp-*`), tipografia, componentes, movimento e pendências
- `assets/`: as duas fotos usadas nos exemplos (pizza e café)

As pranchas são HTML/CSS estáticos que **não rodam sozinhos**: dependem do `support.js` do canvas e de imagens `/_blob/...` que não estão no repositório. Trate-as como um Figma exportado: o HTML e o CSS servem de referência direta, e o `<script type="text/x-dc">` no fim só descreve o estado do protótipo (não é código do app). Não estão no asset pipeline nem são servidas pela aplicação.

**Uso obrigatório pelo `frontend-architect`:**
- Antes de implementar qualquer view, partial ou layout, abrir a prancha correspondente (mapa no `design/jinglepro/README.md`)
- Reproduzir tokens, proporções, estados (hover, focus, disabled, erro, vazio) e movimento conforme a prancha
- Adaptar a sintaxe para ERB + CSS do app + Stimulus, mantendo fidelidade visual
- Cores só como variável CSS `--jp-*`; nada de cor escrita à mão
- Textos e números do protótipo ("R$ 79", "3 rodadas", "20 ajustes", "28 s") **não são fixos**: vêm de `campaign_price`, `Campaigns::MusicRounds::LIMIT`, `config/brands.yml` (`tiers.starter.lyrics_regen_limit`) e da duração escolhida do áudio (`Campaigns::AudioPreview::DEFAULT_DURATION` como padrão, até a música inteira)

**Uso pelo `frontend-analyzer`:**
- Comparar o render real (via Playwright) com a prancha correspondente e validar fidelidade visual, contraste, foco visível e `prefers-reduced-motion` antes do merge

Pendências do design (de `design/jinglepro/README.md`): PNGs das pranchas, mobile dos passos 2 e 3 do Criar, mobile das fases 1 e 3 do Estúdio e o estado "Precisa de atenção" da Biblioteca ainda não foram desenhados.

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
- **frontend-architect**: views ERB e partials, CSS do app (`--jp-*`), Stimulus, acessibilidade (não há ViewComponent no Gemfile)
- Implementa seguindo o plano e fazendo os testes passarem (fase green)

**5. minitest-runner** — após implementação
- Roda os testes e confirma que todos passam
- Diagnostica falhas se houver
- Se a mudança tocar auth, pagamentos, upload de arquivos ou multi-tenant → aciona security-engineer

**6. security-engineer** — quando aplicável
- Revisão de segurança antes do merge
- Obrigatório para: autenticação, autorização, dados sensíveis, integrações externas (Stripe, Mureka, OpenAI)

### Quando usar cada agent diretamente

| Situação | Agent |
|---|---|
| Ideia nova, bug vago ou proposta de refactor | `idea-validator` |
| Ideia validada, pronta para planejar | `task-planner` |
| Plano aprovado, antes de implementar | `tdd-architect` |
| Implementar backend (models, services, APIs) | `backend-architect` |
| Implementar frontend (UI, views ERB/partials) | `frontend-architect` |
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

### Marca e locale (herança do multi-brand: hoje há uma marca e um idioma)
- Existe uma única marca, `b2b`, que é o identificador interno da JinglePro (não significa mais "B2B vs B2C"): `Order::BRANDS` e `User::BRANDS` valem `["b2b"]`, `BRANDS_CONFIG` só tem a chave `:b2b` e `BrandLocaleResolver#detect_brand` sempre retorna `:b2b`. O host da requisição não muda a marca.
- `ApplicationController#set_brand_and_locale` é um `around_action` (não `before_action`). Ele chama `BrandLocaleResolver`, expõe `current_brand` (`"b2b"`) como `helper_method` e roda a request em `I18n.with_locale` com `BRANDS_CONFIG[:b2b][:default_locale]`, ou seja, `pt`. **O locale que o resolver calcula (host `.it`, param em development, cookie, `Accept-Language`) é descartado pelo controller**: na prática o locale é sempre `pt`. Não existe `@brand`; use `current_brand`.
- O layout renderiza `<html lang="pt-BR">` quando `I18n.locale == :pt`. Campanhas são criadas com `locale: "pt"` e `currency` vinda de `brands.yml` (BRL). `Order::CURRENCIES` ainda aceita EUR para pedidos antigos.
- Vestígios que ainda existem: `config.i18n.available_locales` (it, en, es, fr, de, pt), `supported_locales` e `hosts` em `brands.yml`, e `config/locales/brands/b2b/{de,en,es,fr,it}.yml` (sem `pt`). `Order` valida `locale` contra `supported_locales`.
- `t_brand(key)` (em `ApplicationHelper`) tenta `brands.<current_brand>.<key>` e cai na chave global. Hoje só o wizard legado (`orders/wizard/step_1`) o usa; textos novos da campanha ficam em `config/locales/campaign_pt.yml` ou nas views.
- Preços e limites vêm de `config/brands.yml` — **nunca hardcoded**. A campanha usa `campaign_tier: starter`: `price_cents: 2990` (R$ 29,90), `lyrics_regen_limit: 20`, `music_regen_limit: 2`. O limite efetivo de rodadas de música da campanha é `Campaigns::MusicRounds::LIMIT` (3), não `music_regen_limit`. O tier `pro` (stems, soundtrack) é LEGADO.
- Para exibir o preço, use `campaign_price(order = nil)` (`ApplicationHelper`): usa `order.price_cents` quando há pedido (preço congelado na compra) e o `starter` atual caso contrário.

### State machine (AASM)
- Order tem 13 estados (`Order::STATUSES`): 8 funcionais (`pending`, `paid`, `lyrics_drafting`, `lyrics_ready`, `lyrics_approved`, `music_generating`, `preview_ready`, `approved`) e 5 de falha ou encerramento (`payment_failed`, `lyrics_failed`, `music_failed`, `cancelled`, `refunded`). O estado `delivered` que aparece no SPEC antigo não existe no model.
- O vídeo tem estado próprio em `Campaign#video_status` (`pending`, `queued`, `rendering`, `ready`, `failed`), fora da state machine do Order.
- Mapeamento estado → fase do estúdio e → estado da Biblioteca: SPEC.md, seção "Campanha".
- Transições disparam side effects via callbacks `after` / `after_commit`
- Nunca mudar `status` diretamente — sempre via eventos AASM. (Hoje `CampaignsController#retry_generation` e `Campaigns::MusicRounds` ainda fazem `order.update!(status: ...)`; não replique esse padrão.)

### Enums
- **NUNCA** usar `none` como valor de enum — conflita com `ActiveRecord::Base.none`
- Usar `no_adjustment`, `not_applicable`, etc.

### Jobs (Solid Queue)
- Regra: exponential backoff, máx 5 tentativas; ao esgotar, o status vai para `_failed` e o admin é notificado por email
- Estado atual: `ArchiveCampaignAudioJob` e `PrepareCampaignAudioJob` têm 3 tentativas; `StripeWebhookProcessorJob` tem 5 e worker próprio na fila `webhooks`. A geração musical usa `RecoverCampaignMusicJob`. `RecoverInterruptedCampaignJobsJob` recupera letras/vídeos sem atualização há 30 minutos, sem reenviar chamadas de IA já iniciadas. Ambos rodam a cada minuto em produção. `Order#notify_admin` registra log e alerta Sentry quando há DSN; **não há email ao admin**
- Em development o adapter é `:async` (sem worker separado); em production é `:solid_queue` e exige workers e scheduler rodando

### Stripe
- Webhook retorna 200 SEMPRE que a assinatura é válida — processamento é assíncrono (`StripeController#webhook` → `StripeWebhookProcessorJob`)
- Idempotência via tabela `stripe_events` (chave `stripe_event_id`)
- Visitar a `success_url` não confirma pagamento. `CampaignsController#show` reconcilia o pedido `pending` consultando a Stripe (`Stripe::PaymentReconciler`), e ambos os caminhos terminam em `Stripe::CheckoutFulfillment` (valida sessão, valor e moeda antes de `mark_paid!`)
- O botão "Testar sem cobrança" (`POST /campaigns/:id/test_payment`) só existe em development

### Storage
- Hoje: ActiveStorage com serviço Disk. O vídeo é baixado por `GET /campaigns/:id/download`, que exige o dono da campanha, pedido `approved` e `video_status == "ready"` e redireciona para o blob do ActiveStorage; a música aprovada é servida por `OrderAsset#playback_url`
- Meta ao migrar para R2 (ROADMAP, M-4), ainda não implementada: bucket público (previews, samples) com URLs diretas; bucket privado (MP3 completo, vídeo) com signed URLs de 1h; cliente nunca recebe URL direta do bucket privado

### Testes
- Framework: Minitest
- Services: testar `success_result` e `failure_result`
- Clients externos (Mureka, OpenAI, Stripe): usar WebMock
- Jobs: testar enfileiramento e execução
