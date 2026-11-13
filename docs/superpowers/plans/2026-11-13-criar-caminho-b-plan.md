# Criar campanha · caminho B — plano de implementação

- Data: 13/11/2026
- Fonte de verdade: `docs/superpowers/specs/2026-11-13-criar-caminho-b-design.md` (aprovado em 13/11/2026). Este plano não reabre nenhuma decisão dele.
- Fluxo de agentes (CLAUDE.md): `tdd-architect` (testes vermelhos) → `backend-architect` (só onde indicado) → `frontend-architect` → `minitest-runner` → `frontend-analyzer` (tarefa 8) → `security-engineer` (tarefa 9).
- Nenhuma migração, nenhuma rota nova, nenhuma mudança em `campaign_params`.

## Estado de partida

A mudança em andamento (sem commit) é a base. Pontos dela que o plano usa:

- `app/views/campaigns/new.html.erb`: `initial_step = 2` quando a campanha já existe e não tem erros (linha 5); `checkout_started` (`stripe_session_id` presente) remove os passos 1 e 2 e posta para `checkout_order_path` (linhas 4, 21 e 26 a 49); `payment_failed` mostra o aviso e volta ao `:new` (linha 20).
- `app/javascript/controllers/campaign_form_controller.js`: `validate` com trava de duplo clique e `resetSubmission` no `pageshow` (linhas 57 a 76).
- `app/controllers/campaigns_controller.rb`: `create` e `update` terminam em `start_checkout`; `show` renderiza `:new` ou `:payment`; a rota `edit` saiu.
- `app/models/campaign.rb` ganhou o ritmo `natal`, com `config/genre_samples.json` alterado e `public/demos/genres/natal-v1.mp3` ainda **não rastreado**. O arquivo de áudio precisa entrar no commit do passo 0, senão `test/services/campaigns/genre_samples_test.rb` falha em outra máquina.
- `app/views/campaigns/payment.html.erb` (tela "Confirmando pagamento") continua em `studio-app`. Fica fora deste trabalho e vai ao estúdio na fatia 3.

## Passo 0 · Pré-requisito (antes de qualquer tarefa)

1. Commitar a mudança em andamento, incluindo `public/demos/genres/natal-v1.mp3`. Não commitar `output/`, `docs/` (exceto este plano e o design, se o usuário quiser) nem `.claude/launch.json` sem decisão do usuário.
2. Se o working tree mudou desde 13/11/2026, reler `git diff` / `git show HEAD` dos arquivos acima antes de começar. Este plano cita linhas de hoje; elas podem se mover.
3. Rodar `bin/rails test` e `bin/rails test:system` e anotar falhas anteriores. Esse é o baseline: qualquer falha nova depois é nossa.
4. Branch sugerida (o usuário decide; nada foi criado): `feat/criar-caminho-b`, a partir do commit do passo 0. Hoje o trabalho está em `fix/orders-require-login`.
5. As tarefas 1 a 7 ficam **na mesma branch e no mesmo PR**. Entre as tarefas 3 e 7 o Criar fica parcialmente estilizado (a raiz perde `studio-app`, e cada tarefa traz seus componentes). Não publicar commits intermediários.

## Decisões de implementação (valem para todas as tarefas)

**D1. Só classes `ui-` e escopo `.criar`.** O novo markup do Criar não usa nenhuma classe legada (`campaign-builder`, `campaign-main`, `campaign-step`, `campaign-progress`, `campaign-poster*`, `studio-field`, `studio-button`). Motivo, confirmado no código: `studio_app.css` tem regras **sem escopo** (`.campaign-main` linha 185, `.campaign-builder` 189, `.campaign-progress` 190, `.campaign-step h2` 195) e `studio.css` tem `.studio-home h1/h2/p {margin:0}` (linha 6) e `.studio-home h2 {font-size; letter-spacing:-.055em}` (linha 56), com especificidade (0,1,1). Toda regra de `ui.css` entra sob `.criar` (especificidade ≥ (0,2,0)), então vence sem `!important`. Consequência: os testes que usam `form.campaign-builder` passam a usar `form.ui-form` (lista na tarefa 3).

**D2. Layout.** `form.ui-form` é o grid (≥ 960 px: `minmax(0,1fr)` + coluna de prévia de 400 px, guardada numa propriedade local do `ui.css`). Filhos diretos: `ui-head` (barra de passos), três `section.ui-step`, `ui-actionbar` e `ui-side` (coluna da direita). A barra de ação é `sticky` embaixo na coluna 1 no desktop e `fixed` no celular, com `env(safe-area-inset-bottom)`. O passo atual vive em `data-step="1|2|3"` na raiz `.criar` (renderizado no servidor com o `initial_step` para não piscar, e mantido pelo JS no lugar do `campaign-review` de `campaign_form_controller.js:32`). As regras de coluna da direita usam `data-step`.

**D3. Prévia = um único nó, um `<dialog>`.** O `ui-stage` é um `<dialog>` que fica **aberto e não modal** no desktop (JS chama `show()` ao conectar e quando `matchMedia("(min-width: 960px)")` passa a valer) e **fechado** no celular, onde o botão "Ver prévia" chama `showModal()`. Vantagem: um só conjunto de alvos `previewOffer`, `previewPhoto` etc. (nada de alvos duplicados que quebrariam `previewOfferTarget` e os testes que usam o primeiro `[data-campaign-form-target="previewOffer"]`). No desktop, `.criar[data-step="2"|"3"] .ui-stage` some (a coluna mostra o cartão de som ou o de preço). Plano B se a revisão de acessibilidade reprovar um `dialog` sempre aberto: dois nós e alvos plurais (`previewOfferTargets` etc.).

**D4. Cartão do player = um único nó, dentro do passo 2.** Fica logo abaixo da grade de ritmos (posição do celular). No desktop, a `section` do passo 2 vira um grid com as mesmas duas colunas do formulário e o cartão ocupa a coluna 2 (`position: sticky`), enquanto `ui-side` fica oculto no passo 2. Um só `<audio>`, um só `genre-preview`.

**D5. Partials novos** (sugestão; o tdd-architect não depende dos nomes): `app/views/campaigns/new/` com `_saved_sound`, `_notices`, `_steps_bar`, `_promotion` (com `_contact_chips` e `_photo_slots`), `_sound` (com `_player`), `_review`, `_preview`, `_price_card`, `_actionbar`. `campaigns/new.html.erb` fica só com a raiz, cabeçalho, flash, formulário. `_brand_fields`, `_cta_fields`, `_sound_fields`, `_brand_preview`, `_cta_preview` **não são tocados**: o estúdio (`order_chat/_video_appearance` e o painel de som) continua dono deles.

**D6. JS.** `campaign_form_controller.js` cresce com ações novas (ir para passo, abrir/fechar folha, alternar detalhes, escolher contato, somar fotos, preencher resumo, rolar ao topo). Duas mudanças são **obrigatórias** porque o mesmo controller roda no estúdio e no Criar:
- `previewCta()` (linhas 116 a 127) hoje lê `ctaTarget` e `ctaColorTarget`; no Criar não há `select` nem seletor de cor. Ramificar por `hasCtaChoiceTarget` e só recolorir se `hasCtaColorTarget` (no Criar a cor salva já vem do servidor no `style` do painel).
- `logo()` já sai cedo sem `logoInput`; `previewBrand()` precisa continuar com os alvos `previewBusiness` e `previewLogo` presentes (renderizados, mesmo `hidden`).
- Todo texto de lojista entra no DOM com `textContent`, nunca `innerHTML`.
`genre_preview_controller.js` ganha alvos **opcionais** (`hasXTarget`): botão tocar/pausar, tempo atual, duração, onda, nome, descrição. O estúdio continua com o `<audio controls>` nativo.

**D7. Envio como `<button type="submit">`**, não `input[type=submit]`, para levar o SVG da seta. O rótulo fica num `<span>` alvo; `validate`/`resetSubmission` trocam `textContent` em vez de `.value`. O texto passa a ser "Pagar {campaign_price(order)} e criar campanha" (design). Os testes que usam `input[type="submit"][value="Pagar R$ 29,90"]` mudam (lista na tarefa 7). `click_button "Pagar R$ 29,90"` do Capybara continua casando por substring.

**D8. Cabeçalho de página.** O Criar mantém um `h1` com o texto atual ("Sua próxima campanha.") **visualmente oculto** (`ui-sr-only`), porque o título visível de cada passo é `h2` (design) e a página precisa de um `h1`. Isso também preserva o teste `campaign_branding_test.rb:26` (`h1 /Sua próxima campanha/`).

**D9. `field_with_errors`.** Em `.criar`, `.field_with_errors { display: contents }` mantém o layout; o `aria-invalid="true"` e o `aria-describedby` para a mensagem são postos explicitamente nos campos com erro (não se muda o `field_error_proc` global, que serve outras telas).

**D10. Valores nunca fixos.** Preço: `campaign_price(@campaign.order)`. Rodadas: `Campaigns::MusicRounds::LIMIT`. Ajustes: `BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :lyrics_regen_limit)`. Fotos: `Campaigns::PhotoLimit::INITIAL` e `MAX`. Duração do exemplo: `Campaigns::GenreSamples.catalog`. Os limites de 60 e 180 caracteres viram `Campaign::BUSINESS_NAME_MAX_LENGTH` e `Campaign::OFFER_MAX_LENGTH`, usados no model, na view e no contador (hoje o literal está repetido em `campaign.rb` e na view; o contador seria a terceira cópia).

## "Sem faixa" → `show_cta=false` (decisão deixada para quem implementa)

| | A. Atributo virtual em `Campaign` | B. Hidden `show_cta` controlado por JS |
|---|---|---|
| Servidor como fonte de verdade, funciona sem JS | sim | não: sem JS, "Sem faixa" envia `call_to_action=""` com `show_cta=1` e recebe 422 (visível, sem perda de dados) |
| Mexe em `campaign_params` e no model | sim (novo atributo, permit, regra de precedência com `show_cta`) | não |
| Duas fontes para o mesmo dado | sim (atributo virtual × `show_cta`, que o estúdio edita por checkbox) | não |
| Risco para o estúdio | médio (`normalize_display_settings`, `_cta_fields`) | nenhum |
| O servidor já aceita o formato | não | **sim**: `campaign_video_appearance_test.rb:18` posta `show_cta: "0", contact: "", call_to_action: ""` e o estúdio faz o mesmo (`:63`) |

**Recomendação: B.** O Criar já depende de JS para os passos, o design pede "sem mudança no `campaign_params`" e o contrato `show_cta=0` + `call_to_action=""` já é válido e testado. Como fica:

- Um único grupo de rádios nativos `name="campaign[call_to_action]"`: um chip por `Campaign::CTA_OPTIONS`, o chip extra para valor salvo fora da lista (só quando `show_cta?`, igual ao `select` de hoje) e o chip "Sem faixa de contato" com `value=""`.
- `<input type="hidden" name="campaign[show_cta]">` dentro da `section` do passo 1 (o `show()` desabilita e o `validate` reabilita os campos do passo; ficar dentro da section garante o reenvio). Valor inicial renderizado no servidor: `"1"` ou `"0"` conforme `@campaign.show_cta?`; chip "Sem faixa" marcado quando `!show_cta?`. Isso cobre `payment_failed`, cancelamento do checkout e 422.
- Ação `chooseCta` (alvo `ctaChoice` nos rádios): atualiza o hidden para `"0"` se o valor for vazio, senão `"1"`; esconde ou mostra o campo de contato; liga ou desliga `required`; troca `placeholder` e `inputmode` a partir de `data-contact-placeholder` / `data-contact-inputmode` do chip escolhido; atualiza a prévia.
- Os dados de placeholder e `inputmode` por opção vêm de uma constante em `CampaignsHelper` (apresentação, não regra de negócio): WhatsApp e "Reserve seu horário" → `tel`; "Venha nos visitar" → endereço; Instagram → `@`; valor desconhecido → texto genérico.
- O contato digitado é mantido (o campo fica escondido, não desabilitado) e `contact` sem `required` não bloqueia o envio.

Testes dessa decisão (também aparecem nas tarefas 4 e 7):
1. Integração: campanha com `show_cta: false` renderiza `input[type=hidden][name="campaign[show_cta]"][value="0"]`, o rádio `value=""` marcado, `input#campaign_contact:not([required])` e o painel de contato `hidden`. Campanha com `show_cta: true` renderiza `value="1"`, o chip da opção marcado e `#campaign_contact[required]`.
2. Integração: `post campaigns_path` com `show_cta: "0", call_to_action: "", contact: ""` cria a campanha sem `Chamada:` em `order.briefing.about` e com `caption` só com oferta.
3. Sistema: clicar "Sem faixa" põe `"0"` no hidden (`evaluate_script`), esconde o campo e o painel `previewCtaPanel`; voltar a "Peça pelo WhatsApp" devolve `"1"`, `required` e o placeholder; o envio com a Stripe stubada deixa `Campaign.last.show_cta?` falso.

---

## Tarefas

Formato: objetivo, arquivos, testes vermelhos (tdd-architect), pronto quando, agentes, risco para o estúdio e como verificar. "Estúdio" aqui é `/orders/:id/chat`; os testes que o cobrem hoje são `test/integration/campaign_guided_studio_test.rb`, `campaign_creative_flow_test.rb`, `campaign_video_appearance_test.rb`, `campaign_branding_test.rb` (partes do estúdio), `campaign_sound_settings_test.rb`, `campaign_design_regressions_test.rb` (estúdio) e, no sistema, `campaign_guided_studio_test.rb`, `campaign_video_appearance_test.rb` (partes do estúdio) e `campaign_video_personalization_test.rb`. O comando de verificação padrão de cada tarefa é a suíte inteira, mais esse conjunto em destaque.

### Tarefa 1 · Base de CSS (a)

- **Objetivo:** `ui.css` carregado depois de `jinglepro` e dois tokens novos.
- **Arquivos:** `app/assets/stylesheets/ui.css` (novo, começa só com regras escopadas por `.criar` e `ui-`); `app/assets/stylesheets/jinglepro.css` (`:root`: `--jp-on-forest-muted: #B5C9BC` e `--jp-on-forest-line: #3F6253`); `app/views/layouts/application.html.erb:29` (acrescentar `"ui"` depois de `"jinglepro"` na lista do `stylesheet_link_tag`).
- **Atenção:** o layout lista os arquivos pelo nome, **não** usa o glob que o CLAUDE.md descreve. Sem acrescentar `"ui"` na lista a folha não carrega.
- **Testes vermelhos** (`test/integration/criar_css_guard_test.rb`, novo):
  - `get new_campaign_path`: o `link[rel=stylesheet]` de `ui` aparece **depois** do de `jinglepro`.
  - Lê `app/assets/stylesheets/ui.css`: sem `#[0-9a-f]{3,8}`, sem `rgb(`/`rgba(`/`hsl(`, sem `!important`, e todo seletor contém `.criar` ou `.ui-` (checagem grosseira por regex nos preâmbulos de regra).
  - Lê `jinglepro.css`: o `:root` define `--jp-on-forest-muted` e `--jp-on-forest-line` com os dois valores.
- **Pronto quando:** teste passa e a suíte inteira continua verde.
- **Agentes:** tdd-architect → frontend-architect → minitest-runner.
- **Risco para o estúdio:** nulo enquanto todo seletor for `.criar`/`.ui-`; os tokens só acrescentam propriedades. Verificar com a suíte e, na tarefa 8, uma captura do estúdio antes e depois.

### Tarefa 2 · Mover para o estúdio a cobertura de logo e cor (g), antes de remover os campos

- **Objetivo:** tirar do Criar as asserções sobre logo, cor e checkbox de faixa **antes** de os campos sumirem, para a suíte nunca ficar vermelha por motivo alheio. As asserções do lado do estúdio já passam hoje.
- **Por que antes de (c):** reordenei em relação à sugestão (g depois de c). Na ordem original a tarefa 4 quebraria testes que só a tarefa seguinte conserta.
- **Arquivos (só testes):**
  - `test/integration/campaign_branding_test.rb:29`: `input#campaign_logo` sai do bloco do Criar (hoje o `get campaign_path` renderiza o Criar). Acrescentar o par: `get order_chat_path` de um pedido com campanha mostra `input#campaign_logo[type=file]` (o estúdio é exercitado no teste da linha 78; basta uma asserção). As linhas 25, 30 e 31 (`previewLogo[src]`, `previewBusiness[hidden]`) **ficam**: a prévia do Criar continua mostrando a logo salva.
  - `test/integration/campaign_video_appearance_test.rb:27-28`: `#campaign_show_cta:not([checked])` e `#campaign_cta_color[value="#6b21a8"]` saem do Criar. A cor passa a ser afirmada no estúdio (no teste da linha 49, após `get order_chat_path`). O Criar afirma o que o design define: hidden `show_cta=0`, chip "Sem faixa" marcado, `previewCtaPanel[hidden]`. Linha 45 (`#campaign_cta_color[value="#d6f36b"]` após 422, teste da linha 40) vira uma asserção sobre o `style` do painel (`--campaign-cta-color: #d6f36b`) e mantém o `refute_includes "position:fixed"`.
  - `test/system/campaign_video_appearance_test.rb`: reescrever os dois testes do Criar. "merchant can use only a logo…" (linha 43) vira "o lojista deixa o nome em branco": sem `attach_file` de logo e sem "Remover logo do vídeo"; o estúdio já tem o seu equivalente (linha 85). "merchant keeps offer lines and chooses an optional colored strip…" (linha 118) mantém `assert_offer_lines` no Criar (pre-wrap e `R$` + nbsp) e perde `set_color`/`cta_style` (a cor no estúdio já é coberta na linha 162). `uncheck "Incluir faixa de contato no vídeo"` vira "Sem faixa" **na tarefa 4**; nesta tarefa o teste só é marcado como pendente de reescrita e o trecho de cor vai para o estúdio.
- **Contrato de servidor que continua testado (não é UI):** `post campaigns_path` com `logo:` e `cta_color:` continua aceito (`campaign_branding_test.rb:17`, `campaign_video_appearance_test.rb:20`).
- **Pronto quando:** suíte verde com os campos ainda presentes.
- **Agentes:** tdd-architect → minitest-runner (sem implementação).
- **Risco para o estúdio:** nenhum (só testes).

### Tarefa 3 · Casca do Criar (b)

- **Objetivo:** raiz `div.studio-home.criar` sem `studio-app` e sem `campaign-app`; cabeçalho no visual da landing; barra de passos em uma linha; barra de ação; rolagem ao topo e foco no `h2` ao trocar de passo.
- **Arquivos:** `app/views/campaigns/new.html.erb` (reescrito como casca) e `app/views/campaigns/new/_saved_sound`, `_notices`, `_steps_bar`, `_actionbar` (os passos entram nas próximas tarefas; nesta, os três `section` podem reaproveitar o conteúdo atual de forma provisória); `app/assets/stylesheets/ui.css` (`.criar` base, `.ui-head`, `.ui-steps`, `.ui-actionbar`, `.ui-btn`, `.ui-sr-only`, avisos, cabeçalho); `app/javascript/controllers/campaign_form_controller.js` (`data-step`, `stepLabel`, rolagem e foco); `app/views/shared/_studio_header` e `_studio_flash` **sem editar** — cobrir em `ui.css` dentro de `.criar`.
- **Cabeçalho:** `jinglepro.css` estiliza `.studio-header-create`, `.studio-signout` e `.studio-notice`/`.studio-error` só sob `.studio-app` (linhas 27, 28, 39, 40, 313). Sem `.studio-app`, em `.criar` esses itens cairiam no escuro de `studio_app.css:20-23`. `ui.css` precisa de `.criar .studio-app-header`, `.criar .studio-header-create` (pílula floresta), `.criar .studio-signout`, `.criar .studio-notice`, `.criar .studio-error`, mais a versão ≤ 640 px (esconder "Criar promoção", como `jinglepro.css:313`).
- **Barra de passos:** três segmentos + `p` "Passo N de 3 · {título}" numa linha só (`white-space: nowrap`, texto 13 px, piso do README). O texto vem do servidor para o `initial_step` e o JS atualiza o alvo `stepLabel`.
- **Troca de passo (`show(true)`):** `scrollIntoView` do topo do formulário com `behavior: "smooth"` só se `prefers-reduced-motion: no-preference` (hoje a lógica já existe nas linhas 49 a 55, mas rola para o topo da `section`, que no celular fica depois do cabeçalho; rolar para `ui-head`); foco no `h2` com `tabIndex = -1`.
- **Identidade salva:** `@music_profiles` vira linha de chips (links para `new_campaign_path(music_profile_id:)`, nome + `sound_summary`; `aria-current` no ativo; o link "Começar sem identidade salva" quando `@music_profile`).
- **Testes vermelhos:**
  - `test/integration/criar_shell_test.rb` (novo): `get new_campaign_path` → `div.studio-home.criar`; `.studio-app` e `.campaign-app` ausentes; nenhum elemento dentro de `.criar` com classe começando em `campaign-` (guarda contra classe legada); `h1` oculto com "Sua próxima campanha."; cabeçalho com "Minhas campanhas", "Criar promoção" e botão "Sair"; `nav[aria-label="Etapas da campanha"]` com 3 itens e o primeiro `aria-current="step"`; `[data-campaign-form-target="stepLabel"]` = "Passo 1 de 3 · Sua promoção"; `form.ui-form[data-turbo="false"][data-campaign-form-initial-step-value="0"]`; `.criar[data-step="1"]`; barra de ação com "Continuar", "Voltar" (`hidden`) e exatamente um botão `type=submit`; chips de identidade quando há perfil (nome e `sound_summary`).
  - O mesmo arquivo, campanha persistida: `initial_step=2` → `data-step="3"` e `stepLabel` = "Passo 3 de 3 · Conferir"; com `stripe_session_id` o `nav` mostra só o passo 3 (hoje o `nav` mostra os 3; decidir: mostrar "Passo 3 de 3" e manter os 3 segmentos).
  - Migrar seletores `form.campaign-builder` → `form.ui-form` em `campaign_flow_test.rb:18,21,170,194`, `campaign_design_regressions_test.rb:28`, `merchant_journey_test.rb:17,31`, `campaign_branding_test.rb:54`, `test/controllers/pages_controller_test.rb:44`; `.campaign-form-actions` em `test/system/merchant_checkout_test.rb:22` → `.ui-actionbar`; `.campaign-preview-wrap` em `test/system/campaign_video_appearance_test.rb:58,133` → `.ui-stage` (esses dois ficam na tarefa 5).
  - `test/system/criar_navigation_test.rb` (novo): em 1280 e 390 px, rolar até o fim do passo 1, "Continuar" → `window.scrollY` leva o `ui-head` ao topo da janela e `document.activeElement` é o `h2` do passo 2; "Voltar" idem; `stepLabel` cabe numa linha (altura ≤ 1,3 × `line-height`); `scrollWidth <= innerWidth` em 390 px; `data-step` muda com o passo; sem erros de JS (copiar o helper `assert_no_javascript_errors` local, como os outros arquivos fazem).
- **Pronto quando:** testes novos e migrados passam; a captura do cabeçalho do Criar bate com `/` (tarefa 8 confirma).
- **Agentes:** tdd-architect → frontend-architect → minitest-runner.
- **Risco para o estúdio:** o `show()` e o `connect()` de `campaign_form_controller.js` também rodam no formulário `_video_appearance`; todo código novo fica atrás de `hasStepTarget`. Verificar: system `campaign_video_appearance_test.rb` (partes do estúdio) e `campaign_guided_studio_test.rb`.

### Tarefa 4 · Passo 1 · Sua promoção (c)

- **Objetivo:** quatro perguntas: nome, oferta (contador), contato em chips, fotos em espaços que se somam.
- **Arquivos:** `app/views/campaigns/new/_promotion`, `_contact_chips`, `_photo_slots`; `ui.css` (`.ui-field`, `.ui-chip`, `.ui-slots`, `.ui-slot`); `app/helpers/campaigns_helper.rb` (constante e helper de placeholder/`inputmode` por opção); `app/models/campaign.rb` (constantes `OFFER_MAX_LENGTH` e `BUSINESS_NAME_MAX_LENGTH`, usadas nos `validates`); `campaign_form_controller.js`.
- **Campos:** nome (`#campaign_business_name`, label "Nome do seu negócio", `maxlength`, sem `required`, dica "Aparece no vídeo e é cantado na música."); oferta (`#campaign_offer`, `required`, `maxlength`, texto 24 px peso 700, sem alça de redimensionar, contador `n/{OFFER_MAX_LENGTH}` dentro do campo atualizado em `input`); contato conforme a seção "Sem faixa"; manter o rótulo "WhatsApp, endereço ou @Instagram" no campo `#campaign_contact` (os testes de sistema o usam).
- **Fotos:** `Campaigns::PhotoLimit::INITIAL` espaços; o espaço vazio é um `<label for>` do `file_field` múltiplo atual (abre o seletor sem JS), o primeiro com "Abre o vídeo". Manter o nome acessível do input igual ao de hoje ("Fotos do produto ou do negócio (opcional)", via `label` ou `aria-label`) para `attach_file` nos testes de sistema continuar achando. A nota "Logo e cor da faixa você ajusta no estúdio, ao montar o vídeo, sem gastar rodada." fica abaixo.
- **JS das fotos (`photo()` e `renderPhotos()`):**
  - Cada seleção **soma** às fotos já escolhidas nesta visita (estado `this.photos` com `file`), até `photoLimitValue`; `syncPhotoFiles()` regrava o `input.files` com o `DataTransfer`.
  - Lote que estoura o limite ou tem arquivo inválido é **rejeitado inteiro**, a seleção anterior é mantida e a mensagem vai ao `role="status"` ("você já escolheu N de INITIAL"). Hoje o erro limpa a lista (linhas 142 a 155); isso muda e deve estar no teste.
  - Com fotos salvas no servidor, a primeira seleção **substitui** as salvas (a lista `photo_order` some do DOM, o servidor já zera `photo_order` quando chegam `photos`, `campaigns_controller.rb:132`) e o status avisa. Remover todas as novas devolve as salvas (comportamento atual).
  - Setas e "Usar primeiro" continuam botões nativos, restilizados como ícones sobre a miniatura (SVG `aria-hidden`, alvo de 44 px, `aria-label` como hoje). As classes geradas passam de `campaign-photo-*` para `ui-slot*` (essas classes só existem no `campaign-form`; o estúdio usa `video_photos_controller.js`, que **não** muda).
- **Remoção só do Criar:** logo, "Remover logo", checkbox de faixa, seletor de cor, o `select` de CTA. As partials compartilhadas ficam intactas.
- **Testes vermelhos:**
  - `test/integration/criar_promotion_step_test.rb` (novo): campos e `maxlength` vindos das constantes; contador inicial `n/180` com `n = offer.length`; um rádio por `Campaign::CTA_OPTIONS` mais "Sem faixa" (`value=""`), com os textos reais ("Peça pelo WhatsApp", "Venha nos visitar", "Reserve seu horário", "Saiba mais no Instagram"); padrão de campanha nova = WhatsApp marcado; valor salvo fora da lista (a fixture usa "Peça agora") com `show_cta` vira chip extra marcado; com `show_cta: false` não há chip extra e "Sem faixa" vem marcado; `data-contact-placeholder` e `data-contact-inputmode` em cada chip; ausência de `input[type=color]`, `#campaign_logo`, `#campaign_remove_logo`, `#campaign_show_cta` e `select#campaign_call_to_action`; a nota sobre o estúdio; `PhotoLimit::INITIAL` espaços (com o limite stubado em outro valor, o número de espaços acompanha); `input[type=file][multiple][name="campaign[photos][]"]`; texto de ajuda com `INITIAL` e `MAX`; fotos salvas aparecem na ordem de `photo_order` com os hidden `campaign[photo_order][]`.
  - Mesmo arquivo, "não perde dados": campanha com logo anexada e `cta_color: "#6b21a8"`; `patch campaign_path` com **só** os campos do Criar (sem `logo`, `cta_color`, `remove_logo`) mantém logo e cor. É o teste da anti-meta "logo e cor sumirem".
  - `test/models/campaign_test.rb`: as constantes batem com os validadores (60 e 180).
  - `test/helpers/campaigns_helper_test.rb` (novo): dica por opção e fallback para valor desconhecido.
  - `test/system/criar_promotion_step_test.rb` (novo): contador e prévia atualizam ao digitar; chip "Venha nos visitar" troca `placeholder` e `inputmode`; "Sem faixa" (ver seção da decisão); duas chamadas seguidas de `attach_file` somam (`input.files.length` e miniaturas); passar do limite mantém a seleção e anuncia no status; setas e "Usar primeiro" mudam `input.files` na ordem exibida; enviar (Stripe stubada como em `merchant_checkout_test.rb`) grava `product_photos` na ordem mostrada; com foto salva (campanha persistida, voltar ao passo 1), escolher nova foto substitui e o status avisa.
  - Reescrever `test/system/merchant_checkout_test.rb` e `test/system/campaign_video_appearance_test.rb` (trechos do Criar) para as interações novas.
- **Pronto quando:** testes passam; nenhum `campaign-*` dentro de `.criar`; `ui.css` sem `!important`.
- **Agentes:** tdd-architect → backend-architect (só as constantes do model e o helper) → frontend-architect → minitest-runner.
- **Risco para o estúdio:** `_brand_fields` e `_cta_fields` não mudam. O risco está no JS compartilhado (`previewCta`, ver D6) e nas constantes do model (o estúdio valida com elas). Verificar: `test/integration/campaign_video_appearance_test.rb` e `campaign_branding_test.rb` (estúdio), system `campaign_video_appearance_test.rb` (estúdio) e `campaign_video_personalization_test.rb`.

### Tarefa 5 · Prévia em arco e folha "Ver prévia" (d)

- **Objetivo:** coluna da direita do passo 1 e folha do celular nos passos 1 e 3.
- **Arquivos:** `app/views/campaigns/new/_preview`; `ui.css` (`.ui-stage`, `.ui-phone`, `.ui-art`, `.ui-sheet`, botão flutuante); `campaign_form_controller.js` (`openPreview`, `closePreview`, `matchMedia`, `pageshow` fecha a folha).
- **Conteúdo:** arco menta com raio 200/200/18/18; celular 9:16 inclinado 3° com borda creme; etiqueta "Prévia · 9:16"; cartão "Suas fotos. / Sua marca no refrão." da landing; dentro do celular, nome ou logo salva (alvos `previewBusiness` e `previewLogo` sempre renderizados, `hidden` quando vazios), oferta (`previewOffer`, `display_offer` ou "Sua próxima grande oferta."), faixa de contato (`previewCtaPanel`, `previewCta`, `previewContact`) na cor `cta_background_color`/`cta_text_color` vinda do servidor. Sem foto: arte floresta em CSS/SVG com tokens, a oferta em destaque, **sem o glifo "✳"**; com foto, `previewPhoto` aparece e a arte esconde. No celular: botão "Ver prévia" com miniatura da primeira foto (`previewThumb`) acima da barra de ação nos passos 1 e 3, `showModal()`, botão "Voltar a preencher", Esc fecha, foco volta ao botão.
- **Testes vermelhos:**
  - `test/integration/criar_preview_test.rb` (novo): `dialog.ui-stage` existe; exatamente **um** `[data-campaign-form-target="previewOffer"]`; texto = `display_offer` ou o placeholder; `previewBusiness[hidden]` com nome em branco; `previewLogo[src]` com logo salva; `previewCtaPanel` com a cor salva (ex.: `#6b21a8`) e `hidden` com `show_cta` falso; `previewPhoto[src=rails_blob_path(primeira foto)]` com foto salva e `previewPhoto[hidden]` sem; sem foto não há "✳" no corpo; "Prévia · 9:16" e "Sua marca no refrão." presentes; um único botão "Ver prévia".
  - `test/system/criar_preview_test.rb` (novo): em 1280 px, `dialog.open` verdadeiro, `position: sticky`, e a prévia continua na janela depois de rolar; digitar atualiza; em 390 px, `dialog.open` falso e `.ui-stage` invisível (a prévia não aparece mais no fim da página); "Ver prévia" visível nos passos 1 e 3 e ausente no 2; clicar abre como modal, "Voltar a preencher" e Esc fecham e o foco volta ao botão; redimensionar de 390 para 1280 abre o `dialog`; anexar foto põe a miniatura no botão.
  - Atualizar `test/system/campaign_video_appearance_test.rb:58,133` (`.campaign-preview-wrap` → `.ui-stage`, ou removê-las, já que a prévia deixou de ficar no fim da página) e `campaign_flow_test.rb:108` (`img[data-campaign-form-target="previewPhoto"]` continua valendo).
- **Pronto quando:** testes passam; sem `!important`; sem cor à mão.
- **Agentes:** tdd-architect → frontend-architect → minitest-runner.
- **Risco para o estúdio:** as regras `.campaign-poster*` de `jinglepro.css` e `_brand_preview`/`_cta_preview` **não são tocadas**; o Criar usa markup novo. Verificar: `.creative-video-appearance [data-campaign-form-target="previewLogo"|"previewCtaPanel"]` (integração e sistema do estúdio) e `.creative-video-preview` em `campaign_guided_studio_test`.

### Tarefa 6 · Passo 2 · Sua música (e)

- **Objetivo:** tiles de ritmo, voz segmentada, clima em chips, "+ Detalhes do som" e player da marca.
- **Arquivos:** `app/views/campaigns/new/_sound` e `_player`; `ui.css` (`.ui-tile`, `.ui-seg`, `.ui-chip`, `.ui-player`); `app/javascript/controllers/genre_preview_controller.js`; `campaign_form_controller.js` (alternar detalhes, resumo "Sua direção"); `app/services/campaigns/genre_samples.rb` (acrescentar `duration_seconds` ao catálogo, lido do manifesto).
- **Tiles:** um por `Campaign::GENRES` (12 hoje, 4 colunas no desktop e 2 no celular); nome e descrição separados no " · "; "Escolher por mim" com ícone de brilho (SVG `aria-hidden`) e sem descrição. Rádio nativo `required` escondido com a técnica de recorte (clip), **não** `display:none` (um rádio `required` com `display:none` não recebe foco no `reportValidity`). Selecionado = fundo floresta e texto creme, com `:focus-visible` de 3 px. `data-sound-label` passa a levar **só o nome** (hoje leva o rótulo inteiro, ver "Contradições"), e `data-genre-description` leva a descrição.
- **Voz:** `fieldset` com 3 rádios em controle segmentado. **Clima:** 3 chips com nome e descrição de `Campaign::STYLES`, selecionado em lime. **Detalhes:** botão "+ Detalhes do som" (`aria-expanded`, `aria-controls`) que revela o `textarea` `music_notes` (`maxlength` 240, já aberto se houver texto).
- **Player:** cartão floresta com nome e descrição do ritmo, onda de barras fixas (anima só enquanto toca, só `transform`/`opacity`, dentro de `prefers-reduced-motion: no-preference`), botão tocar/pausar lime, tempo atual (`timeupdate`) e duração. O `<audio preload="none">` fica por baixo, **sem `autoplay`** e sem `controls`; a duração mostrada vem de `duration_seconds` do catálogo (formatada com `campaign_media_time`, que já existe em `CampaignsHelper`) e é corrigida por `loadedmetadata`. Escolher ritmo só troca o `src` (o `select()` atual já pausa e recarrega) e **nunca toca**. Sem exemplo, ou "Escolher por mim": o cartão mostra o texto do `hint` no lugar do botão. Erro: "Não foi possível tocar o exemplo" com "Tentar de novo" (`retry()` atual). Nota: "Exemplo com voz ilustrativa. Não gasta rodada." "Sua direção" em chips (nome do ritmo · voz · clima) a partir do cálculo que `show()` já faz (linhas 34 a 39).
- **Testes vermelhos:**
  - `test/services/campaigns/genre_samples_test.rb`: cada item do catálogo tem `duration_seconds` próximo de 12 e igual ao do manifesto. O teste de `business_music_profiles_test.rb:94` stuba o catálogo **sem** `duration_seconds`; a view precisa tolerar a ausência.
  - `test/integration/criar_sound_step_test.rb` (novo): um rádio por `Campaign::GENRES`, cada tile com nome e descrição separados; "Escolher por mim" com ícone `aria-hidden` e sem descrição; marcado = valor da campanha (`pop` na nova, `forro` com perfil salvo); 3 vozes de `VOCAL_GENDERS`; 3 climas de `STYLES` com descrição; botão "+ Detalhes do som" fechado, e aberto quando `music_notes` tem texto; exatamente um `audio[preload=none][data-genre-preview-target=player]` sem `autoplay`; com catálogo stubado `{ "forro" => { url:, label:, duration_seconds: 12.0 } }` o cartão mostra "0:12"; nota "Exemplo com voz ilustrativa. Não gasta rodada."
  - Atualizar `test/integration/business_music_profiles_test.rb:98-99`: o texto "Exemplo do ritmo, com voz ilustrativa" some do Criar e `audio[controls]` deixa de existir; manter `[data-controller="genre-preview"]`, `audio[preload="none"][data-genre-preview-target="player"]` e o `/demos/genres/forro-v1.mp3` no corpo.
  - Teste de não regressão do estúdio (no mesmo arquivo): `get order_chat_path` de um pedido em fase de letra continua renderizando o `_sound_fields` com `audio[controls]` e `[data-genre-preview-target=title]`.
  - `test/system/criar_sound_step_test.rb` (novo): escolher tile por clique **e por seta do teclado** troca `audio.src` e deixa `audio.paused === true`; clicar no botão toca e o tempo atual sai de 0:00; pausar funciona; trocar de ritmo zera o tempo e para o som; trocar de passo pausa e o botão volta a "tocar"; "Escolher por mim" mostra o hint e não mostra o botão; evento `error` disparado em `audio` mostra a mensagem e "Tentar de novo"; em 1280 px o cartão fica à direita dos tiles (retângulo), em 390 px fica entre o último tile e a voz; "+ Detalhes do som" alterna `aria-expanded` e a visibilidade do `textarea`; "Sua direção" acompanha as escolhas. A Mureka não é chamada (já garantido pelo teste de `business_music_profiles`, que verifica `MusicGeneration.count`).
- **Pronto quando:** testes passam e nenhum som toca sem clique (verificado também na tarefa 8).
- **Agentes:** tdd-architect → backend-architect (só `duration_seconds` no catálogo) → frontend-architect → minitest-runner.
- **Risco para o estúdio:** `genre_preview_controller.js` é compartilhado com `_sound_fields` (usado no estúdio e carregado também pelo painel de som). Alvos novos opcionais com `hasXTarget`; `_sound_fields` não muda. A linha 11 de `_sound_fields.html.erb` tem "12 segundos" fixo; é código do estúdio e fica de fora (ver "Contradições"). Verificar: `campaign_sound_settings_test.rb`, `campaign_creative_flow_test.rb`, system do estúdio.

### Tarefa 7 · Passo 3 · Conferir e pagar (f)

- **Objetivo:** resumo editável, cartão de preço, envio na barra de ação e avisos.
- **Arquivos:** `app/views/campaigns/new/_review`, `_price_card`, `_notices`, `_actionbar`; `ui.css` (`.ui-summary`, `.ui-price`, `.ui-alert`); `campaign_form_controller.js` (`goToStep`, `fillSummary`, rótulo do botão); remover as regras `body .campaign-review …` de `jinglepro.css` (linhas 494 a 535, 36 linhas: a classe `campaign-review` não existe mais no Criar; o estúdio não a usa — confirmar com `grep campaign-review app test` antes de apagar).
- **Resumo:** título "Confira e *comece.*" e a frase "Depois do pagamento você revisa a letra e ouve duas versões de música." Três blocos: Promoção (oferta, nome, contato ou "Sem faixa de contato"), Som (`sound_summary` + "Cantada em português do Brasil") e Fotos (miniaturas ou "Sem fotos: criamos uma arte com a sua oferta."). Cada bloco tem "Editar" (`goToStep`, parâmetro do passo); com `checkout_started` o "Editar" não é renderizado e o resumo vem **só do servidor** (os passos 1 e 2 não existem no DOM). Com os passos presentes, o JS reescreve o resumo a cada `show()` com `textContent` a partir dos campos; o texto do som usa só o nome do ritmo (igual a `Campaign#sound_summary`).
- **Cartão de preço (floresta):** "Campanha completa", "PAGAMENTO ÚNICO", `campaign_price(@campaign.order)` em tipo display e a lista: "Até {MusicRounds::LIMIT} rodadas com 2 versões", "Até {lyrics_regen_limit} reescritas com IA e edição livre da letra" (hoje `new.html.erb:53` tem "Até 3 rodadas" fixo), vídeo vertical, MP3 e legenda. Sem botão de pagar no cartão. Manter a frase "Você seguirá para o pagamento seguro pelo Stripe. A criação começa após a confirmação." (usada em `merchant_checkout_test.rb:19`).
- **Envio:** um só `button[type=submit]` na barra de ação, "Pagar {campaign_price} e criar campanha"; `checkout_started` continua postando para `checkout_order_path`. O "Testar sem cobrança" continua fora do `<form>`, só em development.
- **Avisos:** `payment_failed` e erros de validação no topo, com os tokens de atenção, ícone SVG `aria-hidden` e `role="alert"`; campos com erro ganham `aria-invalid="true"` e `aria-describedby` (D9).
- **Testes vermelhos:**
  - `test/integration/criar_review_step_test.rb` (novo): resumo com os três blocos e os valores da campanha; `button` "Editar" por bloco, ausente com `stripe_session_id`; preço = `campaign_price(order)` (com `price_cents: 3990` mostra "R$ 39,90"); limite de rodadas e de reescritas lidos de `Campaigns::MusicRounds::LIMIT` e de `BRANDS_CONFIG` (afirmar contra a constante, não contra "3" e "20"); exatamente um `button[type=submit]` dentro do form, com o texto "Pagar R$ 29,90 e criar campanha"; `form[action=checkout_order_path]` com `checkout_started`; `payment_failed` mostra `[role=alert]` com "O pagamento não foi concluído." e o formulário/resumo vêm preenchidos; 422 com oferta em branco devolve `#campaign_offer[aria-invalid=true]` e o texto de erro, sem perder o nome digitado; "Testar sem cobrança" só em development.
  - Guarda anti-literal: nenhum arquivo em `app/views/campaigns/new*` contém `3 rodadas`, `20 reescritas`, `R$ 29`, `5 fotos` nem `12 segundos`.
  - Atualizar `campaign_flow_test.rb:19-20` (`.campaign-total strong` e `input[type=submit][value=…]`), `:194`, `campaign_design_regressions_test.rb:29`, `merchant_journey_test.rb:32` (`input[type="submit"]` count 0 na tela de espera; com o botão novo, afirmar `button[type=submit]` count 0) e os `click_button "Pagar R$ 29,90"` de sistema (o substring continua casando).
  - `test/system/merchant_checkout_test.rb` (estender): percorre os 3 passos; ao sair do passo 2 o `h2` "Confira e comece." está visível e focado; "Editar" Promoção volta ao passo 1 com os valores e "Continuar" ×2 volta ao 3; o resumo mostra o que foi digitado; envio com `Stripe::Checkout::Session.stub(:create…)` (como o teste atual) leva à letra; em 390 px a barra de ação é `position: fixed` e o último conteúdo não fica escondido atrás dela; a página não tem rolagem horizontal.
  - `test/system/campaign_video_appearance_test.rb:17` (checkout cancelado): continua valendo (só o passo 3, sem "Continuar" e sem "Editar").
- **Pronto quando:** testes passam; `grep -n "campaign-review" app` não acha uso morto.
- **Agentes:** tdd-architect → frontend-architect → minitest-runner.
- **Risco para o estúdio:** a remoção das regras `campaign-review` em `jinglepro.css` só é segura se ninguém mais usar a classe; `campaign_form_controller.js:32` é o único ponto de escrita. `show.html.erb`, `payment.html.erb` e `_delivery` não mudam. Verificar a suíte inteira.

### Tarefa 8 · Passe visual (h) · frontend-analyzer

- Rodar com `bin/dev` já no ar em `http://localhost:3000`, Playwright em 1440×900 e 390×844, comparando contra a landing (`/`) e as pranchas `design/jinglepro/Criar.dc.html` e `Criar-Mobile.dc.html`: cabeçalho, título display com palavra em itálico, arco, celular inclinado, pílulas, floresta/menta/lime.
- Conferir: contraste (`--jp-on-forest-muted` sobre floresta dá ~6,8:1; `--jp-on-forest-line` sobre floresta dá ~1,7:1 e **só pode ser divisória decorativa**, nunca a única borda de um controle), foco visível de 3 px em todos os controles (chips, tiles, segmentos, espaços de foto, setas, player, "Ver prévia"), alvos de 44 px, texto ≥ 13 px, `prefers-reduced-motion: reduce` (sem rolagem suave, sem animação de entrada, onda parada), `[data-motion="off"]` se existir, rolagem horizontal ausente, a onda **parada** com o áudio pausado, e que **nenhum áudio toca sem clique** ao navegar de ritmo.
- Estados: passo 1 vazio e preenchido, chips (incluindo "Sem faixa"), fotos (0, 2 e 5 espaços), prévia sem foto/com foto/com logo, passo 2 com player parado e tocando, passo 3, `payment_failed`, checkout iniciado, erro de validação (422), folha "Ver prévia" no celular.
- Comparar também o estúdio (`/orders/:id/chat`) antes e depois: a captura precisa ser idêntica (nenhuma regra de `ui.css` pode vazar).
- A prancha usa `#EDF0E5` (fundo dos espaços de foto) e `#66796C` (placeholder), que **não são tokens**. Usar `--jp-mint`/`--jp-cream` e `--jp-muted`; o analyzer só reprova diferença visível.
- **Como verificar sem custo (importante):**
  - O app é `http://localhost:3000`. Entrar com um usuário de desenvolvimento (criar a conta é grátis).
  - **Parar no passo 3.** Não clicar em "Pagar … e criar campanha", não apertar Enter com o foco no passo 3 (Enter envia o formulário) e **nunca** clicar em "Testar sem cobrança": em development ele chama `mark_paid!`, que dispara `GenerateLyricsJob` (Mureka paga) com o adapter `:async` rodando dentro do processo.
  - Enter no passo 1 ou 2 só avança de passo (`validate` chama `next()`), é seguro.
  - Os estados "payment_failed" e "checkout iniciado" se montam sem pagar: em `bin/rails runner` (development), criar `Order` + `Campaign` e marcar `status: "payment_failed"` e/ou `stripe_session_id: "cs_fake"`. Abrir `/campaigns/:id` faz a `Stripe::PaymentReconciler` consultar a Stripe com um id inexistente, o que falha sem custo e mostra "A confirmação está demorando". Apagar esses registros depois.
  - Fotos de teste: `public/demos/cafe-aurora.jpg` e `public/icon.png`. Os exemplos de ritmo são arquivos estáticos em `public/demos/genres/`, sem chamada de API.
- **Pronto quando:** o analyzer lista diferenças e todas as de severidade alta são resolvidas pelo frontend-architect.
- **Agentes:** frontend-analyzer → (correções) frontend-architect → minitest-runner.

### Tarefa 9 · Segurança (i) · security-engineer

- **Upload de fotos:** as checagens do navegador (tipo, 10 MB, limite de `INITIAL`) são UX; o servidor continua sendo a barreira (`Campaign#supported_photo`, `valid_photo_order`, `campaign_params`). Conferir que um lote montado por `DataTransfer` não contorna isso (mais de `INITIAL` arquivos, tipo falsificado pelo `Content-Type`, arquivo de 11 MB); testes existentes em `campaign_flow_test.rb` ("server rejects more than five photos…", "server validates the size…").
- **Envio para pagamento:** formulário com `authenticity_token` apesar de `data-turbo="false"`; um só botão de envio e a trava de duplo clique + `pageshow` (`resetSubmission`); preço sempre do servidor (`price_cents` e `currency` do cliente são ignorados, teste em `campaign_flow_test.rb:27`); `set_campaign` escopado ao dono (`not_found` para outro usuário); `photo_order` só aceita permutação das fotos da própria campanha; `update` bloqueado com `stripe_session_id` (`409`).
- **XSS:** oferta, nome, contato e nomes de arquivo entram no resumo, na prévia e nos `alt` via `textContent`/atributos; nenhum `innerHTML`. O `style` do painel de contato só recebe `cta_background_color`/`cta_text_color` já validados pelo model (regex de `#rrggbb`).
- **CSP:** sem script inline novo, sem host novo; `blob:` já permitido para `img_src` e `media_src`. O redirecionamento 303 para `checkout.stripe.com` depende de `form_action` incluir esse host (já incluído).
- **Dados:** o Criar não pode apagar logo nem cor de campanha existente (teste da tarefa 4).
- **Agentes:** security-engineer; correções voltam ao backend-architect/frontend-architect e minitest-runner.

### Tarefa 10 · Documentação (technical-writer, depois do merge das tarefas anteriores)

- `CLAUDE.md`: a linha de CSS (hoje diz que o `stylesheet_link_tag :app` carrega tudo por glob; o layout lista os arquivos) e a nota de que o Criar usa `ui.css` sem `studio-app`. `SPEC.md`, seção "Campanha": passo 1 sem logo/cor, "Sem faixa". Não mexer em mais nada.

---

## Contradições entre o código e o design (para o usuário decidir ou confirmar)

1. **CSS por glob.** O `CLAUDE.md` diz que `stylesheet_link_tag :app` carrega tudo; o layout lista os arquivos pelo nome (`app/views/layouts/application.html.erb:29`). O `ui.css` só carrega se for acrescentado a essa lista.
2. **Duração do exemplo.** O design manda ler a duração de `Campaigns::GenreSamples.catalog`, mas o catálogo só devolve `url` e `label` (`app/services/campaigns/genre_samples.rb:12`). O texto "12 segundos" está fixo em `app/views/campaigns/_sound_fields.html.erb:11` (estúdio, fora do escopo). O plano acrescenta `duration_seconds` ao catálogo (tarefa 6), com a view tolerante a catálogo sem a chave.
3. **Resumo do som.** O `show()` monta o resumo com `data-sound-label`, que hoje é o rótulo inteiro ("Pop · alegre e versátil", `_sound_fields.html.erb:4` e `campaign_form_controller.js:38`), enquanto `Campaign#sound_summary` usa só o nome (`app/models/campaign.rb:135`). O passo 3 e os chips "Sua direção" precisam do nome só.
4. **Rodadas fixas.** `app/views/campaigns/new.html.erb:53` escreve "Até 3 rodadas" (o design exige `Campaigns::MusicRounds::LIMIT`). É um valor fixo na mudança em andamento.
5. **Cor e seletor de CTA no JS.** `campaign_form_controller.js:121-124` assume `ctaTarget` e `ctaColorTarget`; sem os campos o `previewCta()` lança exceção no Criar (D6).
6. **Rótulo do botão de envio.** O design pede "Pagar {preço} e criar campanha"; hoje é "Pagar {preço}" num `input[type=submit]` (`new.html.erb:57`) e vários testes afirmam o `value` exato (tarefa 7).
7. **Erro de foto limpa a lista.** `campaign_form_controller.js:142-155` zera a grade quando o lote é inválido; com seleção somada isso apagaria o que o lojista já escolheu (tarefa 4).
8. **Classe `campaign-review`.** `new.html.erb:6` e `campaign_form_controller.js:32` a alternam, e `jinglepro.css` (linhas 494 a 535) tem 36 linhas de regras para ela. Nada disso sobrevive à casca nova.
9. **Prancha × design.** A prancha `Criar.dc.html` usa `h1` por passo e chips como `button aria-pressed`; o design (e o README) mandam `h2` e rádios nativos. Vale o design.
10. **Tela de espera.** `payment.html.erb` (e `show.html.erb`) seguem no visual antigo com o cabeçalho antigo; é a diferença temporária que o design já aceita (decisão 5), mas ela aparece justamente na volta da Stripe.

## Riscos e armadilhas

- **Rádio escondido e validação:** esconder rádio `required` com `display:none` impede o `reportValidity()` de focar o campo. Usar recorte (clip) e `:focus-visible` no rótulo (`:has(input:focus-visible)` ou irmão adjacente).
- **`disabled` por passo:** `show()` desabilita os campos dos outros passos e `validate` os reabilita antes de enviar. O hidden `show_cta` e qualquer campo novo precisam ficar **dentro** de uma `section` de passo, senão não são enviados.
- **`.studio-home [hidden] { display:none!important }`** (`jinglepro.css:12`) vale em `.criar`: elementos com `hidden` nunca aparecem por `display` de componente; para mostrar, tirar o atributo.
- **Bloco `prefers-reduced-motion: reduce`** de `jinglepro.css:409` já zera animações em `.studio-home *`; o `ui.css` ainda coloca toda animação dentro de `no-preference`, com o estado final como base.
- **bfcache:** ao voltar da Stripe, `pageshow` reabilita o botão (já existe) e deve também fechar a folha de prévia.
- **Dois `<dialog>` não:** a folha e o desktop dividem o mesmo nó (D3); não duplicar alvos `preview*`.
- **`natal-v1.mp3` não rastreado** (passo 0).
- **Tamanho de `ui.css`:** crescer por tarefa, com comentário de seção por componente; é a folha que a fatia 3 herda.

## Ordem das tarefas

0 pré-requisito → 1 base de CSS → 2 mover testes de logo/cor para o estúdio → 3 casca → 4 passo 1 → 5 prévia e folha → 6 passo 2 → 7 passo 3 → 8 passe visual → 9 segurança → 10 documentação.

Plano completo. Próximo passo: invocar o agente **tdd-architect** para desenhar a estratégia de testes e escrever os testes que falham antes de qualquer implementação.
