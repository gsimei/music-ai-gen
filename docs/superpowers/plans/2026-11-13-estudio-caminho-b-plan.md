# Estúdio da campanha · caminho B — plano de implementação

> **Para agentes:** use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans, tarefa por tarefa. Os passos usam caixas (`- [ ]`).

**Objetivo:** o estúdio pós-pagamento em 3 fases (Letra · Músicas · Vídeo), cada uma com um botão principal e um painel "Quero mudar algo". Inclui a duração do vídeo como escolha da fase 3 e a música inteira com marca sonora antes da aprovação.

**Arquitetura:**
- A fase é derivada no servidor por `Campaigns::StudioPhase`. O markup novo fica sob `.estudio`, com componentes `ui-` compartilhados com o Criar.
- Rotas e ações de `order_chat#*` não mudam. A única peça nova de backend é a prévia completa com marca sonora: um anexo, um job e uma ação em `campaign_audio`.
- Os Turbo Streams continuam substituindo `#chat-lyrics-panel` (`OrderChatBroadcaster`). O polling continua em `creation-status`.

**Stack:** Rails 8.1, Hotwire (Turbo + Stimulus via importmap), Propshaft, Minitest + Capybara, FFmpeg.

**Spec:** `docs/superpowers/specs/2026-11-13-estudio-caminho-b-design.md`, aprovado em 13/11/2026. Este plano não reabre nenhuma decisão dele.

**Fluxo de agentes (CLAUDE.md):**
- Para cada tarefa: `tdd-architect` (testes vermelhos), depois `backend-architect` (tarefas 1 e 2) ou `frontend-architect` (3 a 8), depois `minitest-runner`.
- `frontend-analyzer` entra na tarefa 9 e `security-engineer` na tarefa 10.

## Restrições globais

- Valores nunca fixos:
  - rodadas: `Campaigns::MusicRounds::LIMIT` e `order.completed_music_rounds`;
  - ajustes de letra: `order.lyrics_regen_remaining`;
  - fotos: `Campaigns::PhotoLimit::INITIAL`, `MAX`, `SECONDS_PER_PHOTO` e `for_duration`;
  - duração: `asset.track_duration_seconds` e `Campaigns::AudioPreview::DEFAULT_DURATION`;
  - preço: `campaign_price`.
- CSS:
  - só em `app/assets/stylesheets/ui.css`;
  - cores só `var(--jp-*)`, sem `!important`;
  - toda regra escopada em `.criar`, `.estudio` ou `.ui-`;
  - animação só de `transform` e `opacity`, dentro de `@media (prefers-reduced-motion: no-preference)`;
  - foco com 3 px, alvos com 44 px, texto com no mínimo 13 px.
- Nenhum `select` e nenhum `audio[controls]` no markup novo. Nenhum áudio toca sem clique.
- Não mudar `status` direto: só eventos AASM (as ações existentes já cuidam disso). Nenhuma chamada nova de API paga.
- Texto de lojista entra no DOM por `textContent`, nunca por `innerHTML`.
- Testes: `bin/rails test <caminhos explícitos>`. A suíte normal e a de sistema rodam em sequência, nunca em paralelo.

## Foco de revisão

1. Um broadcast que chega enquanto o lojista digita a letra ou ouve uma versão não pode apagar o texto nem parar o áudio. O guard de `creative-editor` continua valendo no markup novo.
2. Cliques seguidos nos chips de duração não podem enfileirar dois preparos. Os chips ficam desabilitados enquanto `campaign_preview_status == "queued"`.
3. A prévia completa nunca sai sem marca:
   - a ação `full` só entrega o anexo `full_audition_audio` cujo `source_blob_id` é `audio.blob.id` e cujo `watermark_version` é `AudioAudition::VERSION`;
   - pedido de outro usuário recebe 404.
4. Com a música mais curta que 30 s, só aparece "Música inteira". Sem rodadas restantes, não aparece nenhum botão que gaste rodada.
5. No celular (375 px), não há rolagem horizontal e a barra fixa não cobre o botão principal nem o último campo.

Cada item tem um teste na tarefa dona, marcado com **(RF n)**.

---

## Passo 0 · Pré-requisito

- [ ] O usuário commita o Criar (`git commit -F tmp/commit-msg-criar.txt`). Nada deste plano começa antes disso.
- [ ] Baseline:
  - suíte normal: `bin/rails test test/models test/services test/jobs test/controllers test/integration test/helpers`;
  - suíte de sistema, em seguida: `bin/rails test test/system`.
  - Anotar as falhas. Hoje são 1198 + 47 testes, 0 falhas, com o flake conhecido de `criar_sound_step_test.rb:80` sob carga.
- [ ] As tarefas 1 a 10 vão na mesma branch, `feat/estudio-caminho-b`, criada a partir do commit do Criar. Entre as tarefas 4 e 8 o estúdio fica parcialmente estilizado; não abrir PR antes da tarefa 10.

## Decisões de implementação (valem para todas as tarefas)

**E1. Fase.** `Campaigns::StudioPhase.for(order)` devolve `:lyrics`, `:music`, `:video`, `:rendering`, `:failed_video` ou `:delivered`. A regra:

| Order | outra condição | fase |
|---|---|---|
| `paid`, `lyrics_drafting`, `lyrics_ready`, `lyrics_failed` | — | `:lyrics` |
| `lyrics_approved`, `music_generating` | — | `:music` |
| `preview_ready`, `music_failed` | sem `campaign.selected_music_asset` | `:music` |
| `preview_ready`, `music_failed` | com `campaign.selected_music_asset` | `:video` |
| `approved` | `video_status` `pending`, `queued` ou `rendering` | `:rendering` |
| `approved` | `video_status` `failed` | `:failed_video` |
| `approved` | `video_status` `ready` | `:delivered` |
| outros (`pending`, `cancelled`, `refunded`, `payment_failed`) | — | `nil` |

- `StudioPhase.step(phase)` devolve o número da barra: `:lyrics` → 1, `:music` → 2, `:video`, `:rendering` e `:failed_video` → 3, `:delivered` → 4.
- O estúdio e `campaigns/show` usam o mesmo objeto. A Biblioteca poderá usá-lo depois; não está neste plano.

**E2. Raiz e casca.**
- `order_chat/show.html.erb` passa a ter `div.estudio`, sem `studio-app`, `jp-workspace` e `jp-workspace-grid`. Ela mantém `data-controller="creation-status"` e os mesmos values, e guarda a fase em `data-phase`.
- O partial `order_chat/_campaign_studio` continua sendo a raiz `#chat-lyrics-panel`, com `data-controller="creative-editor"`. Assim o broadcaster e `right_panel` não mudam.
- `data-creative-editor-view-value` passa a ser o nome da fase, no lugar de `music` ou `video`.
- Partials novos ficam em `app/views/order_chat/studio/`: `_head` (fases e contadores), `_lyrics_phase`, `_music_phase`, `_version_card`, `_more_versions`, `_video_phase`, `_duration_chips`, `_excerpt_timeline`, `_photo_slots`, `_appearance` e `_wait`.
- Os partials antigos que ficarem sem uso são apagados na tarefa da fase que os substitui.

**E3. Componentes compartilhados com o Criar.**
- `campaigns/new/_player` vira `shared/ui/_player`, com os locals `src:`, `title:`, `description:`, `note:`, `duration_seconds:` e `controller:`. O Criar passa `controller: "genre-preview"`; o estúdio passa `controller: "ui-player"`.
- Os fieldsets de ritmo, voz e clima de `campaigns/new/_sound` vão para `shared/ui/_sound_fields`, com o local `f:`. O builder pode ser o do `form_with` do Criar ou o do `fields_for :campaign` do estúdio.
- O Criar continua passando nos testes atuais depois da extração.

**E4. Player do estúdio.**
- Novo `app/javascript/controllers/ui_player_controller.js`, com as ações `toggle`, `tick`, `metadata`, `paused` e `error` e os alvos `toggle`, `current`, `duration`, `wave` e `player`.
- O `<audio>` mantém `data-action="play->creative-editor#play"`, para um player pausar os outros e o guard de broadcast continuar sabendo que há áudio tocando.
- O player também tem `seek(seconds)`, chamado por `excerpt-timeline` para o "Ouvir a partir daqui".

**E5. Prévia completa com marca.**
- O `OrderAsset` ganha `has_one_attached :full_audition_audio` e `full_audition_ready?`. Ela é verdadeira só quando o anexo existe, `metadata["source_blob_id"] == audio.blob.id` e `metadata["watermark_version"] == Campaigns::AudioAudition::VERSION`.
- `full_playback_url` devolve `order_audio_full_path(order, asset_id: id)` se estiver pronta.
- `PrepareFullAuditionJob.perform(asset_id)`:
  - renderiza `Campaigns::AudioAudition.render(source: audio, destination:, start_seconds: 0, duration_seconds: asset.track_duration_seconds)` e anexa o resultado com essa metadata mais `private_order_audio: true`;
  - registra `GenerationCost` local (`operation: "full_audition"`);
  - roda `OrderChatBroadcaster.call` ao terminar;
  - faz 3 tentativas, como `PrepareCampaignAudioJob`;
  - é idempotente: sai cedo se já estiver pronta.
- Quem enfileira é `ArchiveCampaignAudioJob`, nos mesmos dois pontos em que enfileira `PrepareCampaignAudioJob`. Também enfileira para assets antigos sem a prévia completa, quando `order_chat#prepare_audio` é chamado.
- A rota é `get "audio/:asset_id/full", to: "campaign_audio#full", as: :audio_full`, no mesmo escopo de `audio_preview`. A ação `full` usa `set_asset` e `deliver` e responde 404 se `!full_audition_ready?`.

**E6. Duração na fase 3.**
- Cada chip é um `button type="submit"` dentro de um `form_with url: order_chat_excerpt_settings_path, method: :patch`. Ele envia `asset_id`, `preview_revision`, `duration_seconds` (`30`, `60`, `90` ou `full`) e `start_seconds`, este último num hidden preenchido pelo servidor com o início sugerido.
- `ExcerptSettings` não muda. Enquanto prepara, os chips ficam `disabled` e o player mostra "Preparando o trecho…".
- A lista de chips sai de `campaign_duration_chips(asset)`, novo em `CampaignsHelper`. Ele devolve `[{ value:, label:, hint:, photos: }]` só com as durações em que `value <= track_duration_seconds`, mais "Música inteira {m:ss}".
  - O hint do de 30 s é "ideal para Reels e Status".
  - Os outros dizem "até {PhotoLimit.for_duration(v)} fotos".
- `campaign_duration_options` e `campaign_duration_selection` saem quando o `_excerpt_editor` sai.
- A duração exata fica num `input type="text" inputmode="numeric" pattern="\d{1,2}:\d{2}"` (`mm:ss`). O controller `excerpt-timeline` converte para segundos antes do envio e preenche o hidden `duration_seconds`.

**E7. Contadores.**
- O `_head` mostra "Rodadas: {completed_music_rounds} de {LIMIT}" e "Ajustes de letra com IA: {lyrics_regen_remaining}". Em `:rendering` e `:delivered`, só a barra de fases.
- Todo botão que gasta rodada tem, logo abaixo, "Isso usa a rodada {completed + 1} de {LIMIT}." ligado por `aria-describedby`.

**E8. Formatação.**
- `campaign_media_time` continua dando `m:ss`, arredondado.
- O novo `campaign_seconds_label(seconds)` dá "0:15,9", com 1 casa decimal e vírgula, e é usado no valor anunciado da linha do tempo.
- Plurais com `pluralize(n, "foto", plural: "fotos")`.

---

### Task 1: `Campaigns::StudioPhase`

**Arquivos:**
- criar `app/services/campaigns/studio_phase.rb`;
- teste: `test/services/campaigns/studio_phase_test.rb`.

**Interfaces:**
- produz `Campaigns::StudioPhase.for(order) -> Symbol | nil` e `Campaigns::StudioPhase.step(phase) -> Integer | nil` (E1).

- [ ] **Passo 1. Teste.** Um teste por linha da tabela de E1, usando fixtures e `update_columns(status:)` só no setup do teste. Também `step(:video) == 3`, `step(:delivered) == 4` e `for(order sem campanha) == nil`.
- [ ] **Passo 2.** Rodar `bin/rails test test/services/campaigns/studio_phase_test.rb`. Espera-se FAIL por `uninitialized constant Campaigns::StudioPhase`.
- [ ] **Passo 3.** Implementar como módulo com dois métodos de classe; um `case` em `order.status`.
- [ ] **Passo 4.** Rodar o teste e confirmar que passa.
- [ ] **Passo 5.** Commit: `feat: deriva a fase do estúdio em um só lugar`.

### Task 2: prévia completa com marca sonora (backend)

**Arquivos:**
- modificar: `app/models/order_asset.rb`, `app/controllers/campaign_audio_controller.rb`, `config/routes.rb` (linha 28, ao lado de `audio_final`), `app/jobs/archive_campaign_audio_job.rb` (linhas 11 e 25) e `app/controllers/order_chat_controller.rb#prepare_audio` (linhas 145 a 156);
- criar: `app/jobs/prepare_full_audition_job.rb`;
- testes: `test/jobs/prepare_full_audition_job_test.rb`, `test/integration/campaign_audio_access_test.rb` (acrescentar casos) e `test/models/order_asset_test.rb`.

**Interfaces:**
- produz `OrderAsset#full_audition_ready? -> Boolean`, `OrderAsset#full_playback_url -> String | nil`, `PrepareFullAuditionJob.perform_later(asset_id)` e a rota `order_audio_full_path(order, asset_id:)`.

- [ ] **Passo 1. Testes.**
  - Job:
    - com `Campaigns::AudioAudition.stub(:render)` gravando um arquivo, anexa `full_audition_audio` com `source_blob_id == asset.audio.blob.id` e `watermark_version == Campaigns::AudioAudition::VERSION`;
    - chama `render` com `start_seconds: 0` e `duration_seconds: asset.track_duration_seconds`;
    - uma segunda execução não chama `render`.
  - Modelo: `full_audition_ready?` fica falsa quando `source_blob_id` não confere ou a versão da marca muda.
  - Acesso **(RF 3)**:
    - GET `order_audio_full_path` do dono, com a prévia pronta, responde 200, `Cache-Control: private, no-store` e `Content-Disposition` inline;
    - sem a prévia pronta, responde 404;
    - pedido de outro usuário responde 404;
    - pedido em `lyrics_ready` responde 404.
  - Enfileiramento: `ArchiveCampaignAudioJob` enfileira `PrepareFullAuditionJob` (`assert_enqueued_with`).
- [ ] **Passo 2.** Rodar os quatro arquivos. Espera-se FAIL (rota, constante e método inexistentes).
- [ ] **Passo 3.** Implementar conforme E5. A conversão é a mesma de `PrepareCampaignAudioJob`: `asset.audio.blob.open`, `Dir.mktmpdir`, anexar dentro de `asset.with_lock`. Sem lógica de revisão: a prévia completa depende só do áudio original.
- [ ] **Passo 4.** Rodar os testes e confirmar que passam. Depois, `test/integration/campaign_excerpt_test.rb` e `test/jobs` inteiros, sem falha nova.
- [ ] **Passo 5.** Commit: `feat: prévia da música inteira com marca sonora`.

### Task 3: base `.estudio` e componentes compartilhados

**Arquivos:**
- modificar: `app/assets/stylesheets/ui.css`, `test/integration/criar_css_guard_test.rb`, `app/views/campaigns/new/_sound.html.erb` e `app/views/campaigns/new/_player.html.erb` (vira chamada ao shared);
- criar: `app/views/shared/ui/_player.html.erb`, `app/views/shared/ui/_sound_fields.html.erb` e `app/javascript/controllers/ui_player_controller.js`;
- teste: `test/integration/criar_css_guard_test.rb`.

**Interfaces:**
- produz os partials de E3 e o controller `ui-player` de E4, com o método público `seek(seconds)`.

- [ ] **Passo 1. Teste.** A guarda aceita seletor que comece com `.criar`, `.estudio`, `.ui-` ou `html:has(.criar|.estudio)`. Ela continua recusando seletor sem escopo; o teste prova isso com um exemplo inline.
- [ ] **Passo 2.** Rodar a guarda. Espera-se FAIL só no caso novo.
- [ ] **Passo 3.** Ampliar a regex da guarda. Mover `.criar .ui-player*`, `.ui-tiles` e `.ui-seg` para seletores `:is(.criar, .estudio)`. Extrair os partials e escrever `ui_player_controller.js` com os mesmos nomes de alvo do `genre-preview`.
- [ ] **Passo 4.** Rodar a guarda e os testes do Criar: `test/integration/criar_*_test.rb test/system/criar_sound_step_test.rb test/integration/campaign_flow_test.rb`. Tudo passa.
- [ ] **Passo 5.** Commit: `refactor: player e campos de som compartilhados entre Criar e estúdio`.

### Task 4: casca, barra de fases e contadores

**Arquivos:**
- modificar: `app/views/order_chat/show.html.erb` e `app/views/order_chat/_campaign_studio.html.erb`;
- criar: `app/views/order_chat/studio/_head.html.erb` e `app/views/order_chat/studio/_wait.html.erb`;
- testes: `test/integration/estudio_shell_test.rb` (novo), `test/integration/campaign_guided_studio_test.rb` e `test/integration/studio_interface_test.rb` (migrar seletores).

**Interfaces:**
- consome `StudioPhase.for/step`;
- produz `div.estudio[data-phase]`, `#chat-lyrics-panel[data-creative-editor-view-value=<fase>]` e o partial `order_chat/studio/wait` (locals `title:`, `detail:`, `notes:`).

- [ ] **Passo 1. Testes.**
  - Para `lyrics_ready`, `preview_ready` sem seleção e `preview_ready` com seleção: a barra tem três itens, "Letra", "Músicas" e "Vídeo", e `aria-current="step"` está no item certo.
  - O texto "Rodadas: N de {LIMIT}" e "Ajustes de letra com IA: {remaining}" bate com o pedido. O teste muda `completed_music_rounds` e `lyrics_regen_remaining` para provar que não é fixo.
  - Em `lyrics_approved`, o estúdio mostra "Criando duas versões" e "1 a 2 minutos".
  - Não há `.studio-app` dentro de `.estudio`.
- [ ] **Passo 2.** Rodar. Espera-se FAIL.
- [ ] **Passo 3.** Implementar a casca (E2), o `_head` (E7) e o `_wait`, este com os avisos `rate_limited` e `status_unavailable` de `_creation_status` como linhas do cartão. `_campaign_studio` vira um `case` na fase, que renderiza os partials atuais até as tarefas 5 a 7 os trocarem.
- [ ] **Passo 4.** Rodar o teste novo e os de estúdio: `campaign_guided_studio_test`, `studio_interface_test`, `campaign_creative_flow_test`, `campaign_chat_direction_test` e `chat_creation_flow_test`, migrando só seletores.
- [ ] **Passo 5.** Commit: `feat: casca do estúdio com fases e contadores`.

### Task 5: fase 1 · Letra

**Arquivos:**
- criar: `app/views/order_chat/studio/_lyrics_phase.html.erb`;
- remover: `_creation_form`, `_campaign_lyrics` e `_creation_status` (o conteúdo vai para `_lyrics_phase` e `_wait`);
- modificar: `app/javascript/controllers/creative_editor_controller.js` (só se o form da letra mudar de classe);
- testes: `test/integration/estudio_lyrics_phase_test.rb` (novo), `campaign_creative_flow_test.rb` e `campaign_sound_settings_test.rb`.

**Interfaces:**
- consome `shared/ui/_sound_fields` e o `_wait`;
- os formulários postam para as ações de hoje:
  - "Aprovar" é `order_chat_creation_path` com `intent=generate`, que salva o texto e aprova (Decisão 5 do spec);
  - "Salvar letra" usa `intent=save`;
  - "Reescrever" usa `intent=rewrite` com `lyrics_feedback`;
  - o som vai em `campaign[...]` no mesmo form.

- [ ] **Passo 1. Testes.**
  - Em `lyrics_ready`:
    - `h2` "Revise a letra.";
    - um só botão `.ui-btn-primary` com o texto "Aprovar letra e ouvir 2 versões";
    - logo abaixo, "Isso usa a rodada 1 de {LIMIT}.";
    - `details` "Quero mudar algo", fechado, com o pedido à IA ("Reescrever com IA · {N} ajustes") e os tiles de ritmo (`input[type=radio][name="campaign[musical_genre]"]`).
  - Sem `select`.
  - Com `lyrics_regen_exhausted?`, o painel não oferece reescrita.
  - Em `lyrics_failed`, aparece "Tentar preparar a letra novamente".
  - POST com `intent=generate` e o texto editado salva o rascunho novo e aprova; o teste atual de `campaign_creative_flow_test` cobre o fluxo e migra o seletor.
  - **(RF 1, sistema):** em `test/system/campaign_guided_studio_test.rb`, o lojista digita na letra, um `OrderChatBroadcaster.call` roda e o texto continua no campo.
- [ ] **Passo 2.** Rodar. Espera-se FAIL.
- [ ] **Passo 3.** Implementar. Os IDs que `creative-editor` usa para reabrir `details` (`creation-sound`, `rewrite-lyrics`) continuam nos novos `details`.
- [ ] **Passo 4.** Rodar os testes da tarefa e os de estúdio da tarefa 4.
- [ ] **Passo 5.** Commit: `feat: fase da letra no estúdio`.

### Task 6: fase 2 · Músicas

**Arquivos:**
- criar: `app/views/order_chat/studio/_music_phase.html.erb`, `_version_card.html.erb` e `_more_versions.html.erb`;
- remover: `_music_choices` e `_music_audition`;
- testes: `test/integration/estudio_music_phase_test.rb` (novo), `campaign_guided_studio_test.rb` e `campaign_audio_access_test.rb` (seletores).

**Interfaces:**
- consome `shared/ui/_player`, `ui-player` e `OrderAsset#full_playback_url`;
- "Usar a Versão X" posta para `order_chat_select_music_path(asset_id:)`;
- "Criar mais duas versões" posta para `order_chat_creation_path` com `intent=generate`, `feedback` e `campaign[...]`;
- "← Voltar à letra" é um link com `#estudio-change` que abre o `details` "Quero mudar algo" no item da letra (Decisão 9 do spec).

- [ ] **Passo 1. Testes.**
  - Em `preview_ready` com 1 rodada: dois cartões, "Versão A" e "Versão B", cada um com `.ui-player` e sem `audio[controls]`.
  - Com a prévia completa pronta, cada cartão mostra "Música completa {m:ss}" e o botão "Ouvir completa" aponta para `order_audio_full_path`. Sem a prévia completa, mostra só a duração.
  - Um único botão primário, "Usar a Versão A e montar o vídeo", e os rádios dos cartões trocam o asset do form. O fallback sem JS é um botão por cartão; o teste afirma que existe pelo menos um form para cada asset.
  - "Quero mudar algo":
    - tem chips de pedido rápido;
    - tem o campo `feedback` com `maxlength=400`;
    - tem "Criar mais duas versões";
    - tem "Isso usa a rodada 2 de {LIMIT}.".
  - **(RF 4):** com `completed_music_rounds == LIMIT`, não há botão "Criar mais duas versões" e aparece o texto de rodadas esgotadas.
  - Rodadas anteriores ficam num `details` "Rodada N".
  - Em `music_failed`, aparecem "Esta tentativa não ficou pronta." e o botão "Tentar novamente".
- [ ] **Passo 2.** Rodar. Espera-se FAIL.
- [ ] **Passo 3.** Implementar. Os chips de pedido rápido preenchem `feedback` com `creative-editor#suggest`, que já existe.
- [ ] **Passo 4.** Rodar os testes da tarefa e os de estúdio da tarefa 4.
- [ ] **Passo 5.** Commit: `feat: fase das músicas no estúdio`.

### Task 7: fase 3 · Vídeo (duração, trecho, fotos e aparência)

**Arquivos:**
- criar:
  - `app/views/order_chat/studio/_video_phase.html.erb`, `_duration_chips.html.erb`, `_excerpt_timeline.html.erb`, `_photo_slots.html.erb` e `_appearance.html.erb`;
  - `app/javascript/controllers/excerpt_timeline_controller.js`;
- remover: `_video_setup`, `_excerpt_editor`, `_video_photos`, `_video_appearance`, `app/javascript/controllers/audio_excerpt_controller.js` e `campaign_duration_options`/`campaign_duration_selection`;
- modificar:
  - `app/helpers/campaigns_helper.rb` (`campaign_duration_chips` e `campaign_seconds_label`);
  - `app/javascript/controllers/video_photos_controller.js` (renderizar espaços `ui-slot` até o limite);
- testes:
  - `test/helpers/campaigns_helper_test.rb`;
  - `test/integration/estudio_video_phase_test.rb` (novo);
  - migrar seletores em `campaign_excerpt_test.rb`, `campaign_video_appearance_test.rb`, `test/system/campaign_video_personalization_test.rb` e `test/system/campaign_video_appearance_test.rb`.

**Interfaces:**
- consome:
  - `ExcerptSettings` via `order_chat_excerpt_settings_path`;
  - `order_chat_video_photos_path` e `order_chat_video_appearance_path`, com os mesmos parâmetros de hoje;
  - `order_chat_change_music_path` ("← Voltar às músicas");
  - `order_chat_approve_music_path` ("Gerar meu vídeo", com os mesmos params);
  - `ui-player#seek`;
- produz `campaign_duration_chips(asset) -> Array<Hash>` e `campaign_seconds_label(Float) -> String` (E6, E8).

- [ ] **Passo 1. Testes.**
  - Helper:
    - para uma faixa de 66 s, os chips são `["30", "60", "full"]`, com "até {PhotoLimit.for_duration(60)} fotos" e "Música inteira 1:06";
    - **(RF 4):** para uma faixa de 20 s, só `["full"]`;
    - `campaign_seconds_label(15.870000000000001) == "0:15,9"`.
  - Integração:
    - os chips são botões de submit, e o de 30 s tem `aria-pressed="true"` por padrão;
    - **(RF 2):** com `campaign_preview_status == "queued"`, todos os chips e o "Gerar meu vídeo" ficam `disabled`;
    - os espaços de foto (`.ui-slot`) são `photo_limit` no total, e o texto "+{n} espaços liberados" aparece quando o limite passa de `INITIAL`;
    - "1 foto" no singular;
    - "Mudar onde começa" tem um `input[type=range]` com `aria-valuetext` em `m:ss` e "Ouvir a partir daqui";
    - a duração exata é `input[pattern]` em `mm:ss`;
    - a linha do tempo marca as seções de `asset.lyrics_sync["sections"]` ("Verso", "Refrão"), posicionadas em % de `track_duration_seconds`; sem `lyrics_sync`, não há marcas e nada quebra;
    - a prévia 9:16 (`.ui-stage`) mostra a primeira foto, o nome ou logo, a oferta e a faixa;
    - com fotos demais para a duração, "Gerar meu vídeo" fica `disabled` e o motivo aparece visível;
    - sem `select` e sem `audio[controls]`.
  - Sistema: escolher "1 min" envia o form e mostra "Preparando o trecho…"; a resposta é stubada, sem FFmpeg.
- [ ] **Passo 2.** Rodar. Espera-se FAIL.
- [ ] **Passo 3.** Implementar conforme E6.
  - `excerpt-timeline` move o hidden `start_seconds` e chama o `seek` do player da prévia completa quando ela existe. Sem ela, o botão "Ouvir a partir daqui" fica oculto.
  - "Aparência do vídeo" reaproveita `campaigns/_brand_fields` e `_cta_fields`, restilizados com classes `ui-` dentro de `.estudio`. Os nomes dos campos não mudam.
- [ ] **Passo 4.** Rodar os testes da tarefa e todos os de estúdio, incluindo os de sistema (`campaign_video_*`).
- [ ] **Passo 5.** Commit: `feat: fase do vídeo com duração em primeira linha`.

### Task 8: montando, falha do vídeo e Entrega em `campaigns/show`

**Arquivos:**
- modificar: `app/views/campaigns/show.html.erb` e `app/views/campaigns/_delivery.html.erb`;
- testes: `test/integration/campaign_flow_test.rb`, `test/integration/campaign_branding_test.rb` (seletores) e `test/integration/estudio_delivery_test.rb` (novo).

**Interfaces:**
- consome `StudioPhase` e `order_chat/studio/_head`, com um local `counters: false`;
- `#campaign-delivery`, `campaigns#status` e o `creation-status` interno não mudam.

- [ ] **Passo 1. Testes.**
  - `approved` com `video_status` `queued`: raiz `.estudio`, a barra com "Vídeo" em `aria-current` e o checklist com "Música escolhida · trecho de {m:ss}".
  - Com `video_status` `failed`: "A música está salva." e "Tentar montar o vídeo novamente".
  - Com `video_status` `ready`: o quarto item, "Entrega", fica ativo, com "Baixar vídeo MP4", "Baixar música MP3" e "Copiar legenda".
  - Antes de `approved`, `show` continua com o link "Acompanhar e escolher a música" para o estúdio.
- [ ] **Passo 2.** Rodar. Espera-se FAIL.
- [ ] **Passo 3.** Implementar seguindo a prancha `Entrega`. Se o reskin completo da Entrega passar de cerca de 150 linhas de diff, ele sai deste PR e fica só a casca com a barra (Decisão 7 do spec). Registrar a decisão no PR.
- [ ] **Passo 4.** Rodar os testes da tarefa e `test/system/campaign_*`.
- [ ] **Passo 5.** Commit: `feat: acompanhamento e entrega com a casca do estúdio`.

### Task 9: celular e revisão visual

**Arquivos:**
- modificar: `ui.css` (bloco `.estudio`, menor que 960 px);
- teste: `test/system/estudio_mobile_test.rb` (novo).

- [ ] **Passo 1. Teste (RF 5).** Em 375 × 812, nas fases 1, 2 e 3:
  - `document.documentElement.scrollWidth <= innerWidth`;
  - a barra de ação fixa contém o botão principal da fase;
  - o último campo do "Quero mudar algo" aberto fica visível depois de `scrollIntoView`, porque `scroll-padding-bottom` cobre a barra.
  - O teardown chama `clearDeviceMetricsOverride` antes de `Warden.test_reset!`.
- [ ] **Passo 2.** Rodar. Espera-se FAIL.
- [ ] **Passo 3.** Implementar a barra fixa com `env(safe-area-inset-bottom)` e `html:has(.estudio){scroll-padding-bottom: …}`, como no Criar.
- [ ] **Passo 4.** Rodar o teste.
- [ ] **Passo 5.** `frontend-analyzer`: comparar com `design/jinglepro/Estudio.dc.html`, `Estudio-Mobile.dc.html` e `Entrega.dc.html`, usando os pedidos locais 69 (`lyrics_ready`) e 71 (`preview_ready`). Verificar contraste, foco visível e `prefers-reduced-motion`. Corrigir o que ele apontar, na mesma tarefa.
- [ ] **Passo 6.** Commit: `feat: estúdio no celular`.

### Task 10: segurança, suíte completa e documentação

- [ ] **Passo 1.** `security-engineer` sobre a tarefa 2 e as views novas:
  - a prévia completa sempre tem marca e cobre a faixa inteira;
  - só o dono acessa;
  - `no-store`;
  - nenhum texto de lojista via `innerHTML`.
  - Corrigir o que for bloqueante.
- [ ] **Passo 2.** Suíte normal, e depois a de sistema, em sequência. Só aceitar falhas que já estavam no baseline do passo 0.
- [ ] **Passo 3.** `SPEC.md` 0.4:
  - a coluna "Fase do estúdio" passa a citar `Campaigns::StudioPhase` e os nomes "Letra", "Músicas" e "Vídeo";
  - `lyrics_approved` passa para a fase 2, decisão confirmada.
- [ ] **Passo 4.** `ROADMAP.md`:
  - a fatia 3 fica `[x]`, com o que ficou fora (Entrega, se cortada; Biblioteca usando `StudioPhase`);
  - entra o achado do prompt da Mureka: introdução de cerca de 16 s sem voz e faixas de 66 s e 163 s para um pedido de 30 s.
  - `CLAUDE.md`, seção Stack e nota do `order_chat`: o estúdio novo vive em `order_chat/studio/`.
- [ ] **Passo 5.** Commit: `docs: estúdio caminho B`. Depois, `superpowers:finishing-a-development-branch`.
