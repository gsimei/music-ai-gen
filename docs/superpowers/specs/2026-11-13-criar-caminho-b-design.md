# Criar campanha · caminho B (design)

- Data: 13/11/2026
- Estado: aguardando aprovação
- Origem: proposta "Novo fluxo de criação" (https://claude.ai/artifact/TtTh7MeqXVvXRSP77nmQDz). O caminho B foi escolhido em 13/11/2026.

## Intenção

O lojista sai da landing, clica em "Criar campanha" e cai em outra marca: um formulário de coluna estreita, com aparência antiga e campos estranhos (upload em pílula, `select`, checkbox e seletor de cor nativos, rádios com bolinha, player cinza do navegador). O objetivo é que o Criar fale a mesma língua visual da landing e que o passo 1 fique mais curto. A campanha salva, o preço e o pagamento continuam iguais.

A causa é estrutural: o estúdio nasceu escuro (`studio_app.css`) e foi repintado de claro por cima (`jinglepro.css`, com 175 seletores `body .studio-app` só para vencer as regras antigas). Remendar componente por componente continua essa briga de especificidade. Por isso o Criar ganha uma base nova, que não herda essas regras.

## Metas

1. `campaigns/new` (e os estados que renderizam `:new`: checkout cancelado, `payment_failed`, checkout já iniciado) com a linguagem da landing: título display com uma palavra em itálico, arco menta com o celular inclinado, pílulas com seta, blocos floresta, menta e lime.
2. Passo 1 com 4 perguntas: nome do negócio, oferta, contato e fotos.
3. Um conjunto de componentes reutilizável na fatia 3 (estúdio e entrega): campo, chip, tile, controle segmentado, espaços de foto, player da marca, barra de passos, barra de ação, prévia em arco e folha de prévia no celular.
4. Corrigir o que vimos no teste: a rolagem não volta ao topo ao trocar de passo; a prévia fica depois do botão no celular; o indicador de passos quebra em duas linhas; a prévia sem foto parece imagem quebrada.

## Não-metas

- Estúdio (letra, músicas, vídeo) e entrega: ficam para a fatia 3. Continuam com o CSS atual e precisam continuar funcionando.
- Landing: não muda.
- Remover o Tailwind, o `studio_app.css` ou o `jinglepro.css`. Eles continuam servindo as outras telas.
- Mudar o modelo de dados, preço, checkout ou rotas. Nenhuma migração.
- Criar a conta no passo 3, como sugere a prancha `Criar`.

## Anti-metas (falha mesmo que funcione)

- Quebrar o estúdio, a biblioteca, o login ou qualquer tela que use os CSS atuais.
- Perder dados: a logo e a cor de campanhas existentes sumirem, ou o formulário voltar vazio depois de `payment_failed`.
- Cor escrita à mão no CSS, ou texto e número fixos (preço, rodadas, 20 ajustes, 5 fotos, 12 segundos).
- Som tocando sem a pessoa pedir.
- Regredir em acessibilidade: `label` real, foco visível de 3 px, `aria-invalid` com `role="alert"`, alvos de 44 px e `prefers-reduced-motion`.

## Restrições

- Tokens, tipografia, componentes e movimento seguem `design/jinglepro/README.md`. Cores só como `--jp-*`. Escolhas com rádios nativos estilizados. Ícones SVG com `aria-hidden`.
- Valores vêm de `campaign_price(@campaign.order)`, `Campaigns::MusicRounds::LIMIT`, `BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :lyrics_regen_limit)`, `Campaigns::PhotoLimit::INITIAL` e da duração do exemplo em `Campaigns::GenreSamples.catalog`.
- `call_to_action` entra no briefing da música (`Campaign#about`) e na legenda. Por isso o contato fica no Criar.
- Logo e `cta_color` só afetam o vídeo. O estúdio já os edita em "Aparência do vídeo" (`order_chat/_video_appearance`, que renderiza `campaigns/_brand_fields` e `campaigns/_cta_fields`).
- `BusinessMusicProfile#campaign_attributes` traz nome, ritmo, voz, clima e notas. Não traz logo nem cor, então "identidade salva" não é afetada.
- O formulário do Criar não usa Turbo (`data: { turbo: false }`), porque o envio termina num redirecionamento para a Stripe.
- Base: a mudança em andamento (sem commit em 13/11/2026), que leva o envio direto para a Stripe, reaproveita o passo 3 para checkout iniciado e `payment_failed` e remove a rota `edit`. Este design parte dela.
- Fluxo de agentes do `CLAUDE.md`: task-planner → tdd-architect → frontend-architect → frontend-analyzer → minitest-runner → security-engineer (o envio toca upload e pagamento).

## Abordagens consideradas

| | O que é | Ganha | Custa |
|---|---|---|---|
| A. Repaginar | Componentes novos e CSS unificado, mesmos campos e passos | Menor risco; testes quase intactos | Passo 1 continua com 8 decisões |
| **B. Enxugar e repaginar (escolhido)** | A, mais: logo, cor e faixa saem do Criar; contato vira chips; a coluna da direita muda por passo | Passo 1 com 4 perguntas; mesmos 3 passos e mesmos dados | Mexe no Stimulus `campaign-form` e em alguns testes |
| C. Uma pergunta por tela | 6 ou 7 telas curtas, estilo conversa | O mais diferente | Mais cliques até pagar; reescrita maior; a prévia perde o lugar fixo |

O usuário escolheu B depois de ver a proposta com prints e mockups.

## Design

### Isolamento do CSS

- Nova folha `app/assets/stylesheets/ui.css`, carregada depois de `jinglepro` no `stylesheet_link_tag` do layout. Classes com prefixo `ui-` (`ui-field`, `ui-chip`, `ui-tile`, `ui-seg`, `ui-slots`, `ui-player`, `ui-steps`, `ui-actionbar`, `ui-stage`, `ui-sheet`, `ui-btn`).
- A raiz do Criar passa a ser `<div class="studio-home criar">`, **sem** `studio-app` e sem `campaign-app`. Assim nenhuma das regras `body .studio-app …` e `.campaign-app …` se aplica.
- Os tokens continuam no `:root` de `jinglepro.css`. Entram só os que faltam para superfícies floresta: texto atenuado sobre floresta (`#B5C9BC`) e divisória sobre floresta (`#3F6253`), com nomes `--jp-*`.
- Cabeçalho: dentro de `.criar`, o `shared/_studio_header` ganha o visual da navegação da landing (logo, "Minhas campanhas", "Criar promoção" em pílula, "Sair"), com regras em `ui.css` escopadas por `.criar`. As outras telas mantêm o cabeçalho atual até a fatia 3. Essa diferença temporária é aceita.

### Estrutura da página

- Desktop (≥ 960 px): duas colunas, formulário e coluna de prévia de 400 px que acompanha a rolagem (`position: sticky`). Celular: uma coluna.
- Topo do formulário: barra de 3 segmentos e o texto "Passo 1 de 3 · Sua promoção", sempre em uma linha.
- Cada passo abre com rótulo pequeno, uma pergunta em tipo display (cerca de 58 px no desktop e 38 px no celular) com uma palavra em Cormorant itálico e uma frase de apoio.
- Barra de ação fixa no rodapé da coluna do formulário: "Voltar" (contorno) e o botão principal (pílula floresta com seta). No passo 3 o botão principal é o envio, com o texto "Pagar {campaign_price} e criar campanha".
- Ao trocar de passo, a página rola até o topo do formulário (suave só com `prefers-reduced-motion: no-preference`) e o foco vai para o título do passo, como hoje.
- "Comece com o som do seu negócio" (identidade salva) vira uma linha de chips acima do passo 1, cada um com nome e resumo do som.

### Passo 1 · Sua promoção

1. **Nome do negócio** (opcional, 60 caracteres). Dica: "Aparece no vídeo e é cantado na música."
2. **Oferta** (obrigatória, 180 caracteres): campo grande, texto em 24 px peso 700, contador "n/180" dentro do campo, sem alça de redimensionar.
3. **Contato**: um grupo de rádios nativos em chips, um por opção de `Campaign::CTA_OPTIONS`, mais "Sem faixa de contato". Um valor salvo fora da lista aparece como chip extra, como acontece hoje no `select`. "Sem faixa" desliga `show_cta` e esconde o campo de contato. Para as outras opções, o campo de contato mostra placeholder e `inputmode` próprios (telefone para WhatsApp e reserva, endereço para visita, `@` para Instagram) e é obrigatório.
4. **Fotos** (opcional): grade de `Campaigns::PhotoLimit::INITIAL` espaços com miniatura. O primeiro leva a etiqueta "Abre o vídeo". Um espaço vazio abre o seletor de arquivos (o mesmo `file_field` múltiplo de hoje). As fotos escolhidas **se somam** às já selecionadas nesta visita, até o limite, usando o `DataTransfer` que o controller já usa para reordenar e remover. Hoje cada seleção substitui todas, o que não combina com espaços vazios. Com fotos já salvas no servidor (volta de `payment_failed`), escolher novas continua substituindo as salvas, como hoje e como o servidor espera (`photo_order` zerado quando chegam `photos`), e o texto de status avisa isso. A ordem muda com os botões atuais (setas e "Usar primeiro"), restilizados como ícones sobre a miniatura. Não há arrastar. Mensagens de limite e tamanho continuam no texto de status (`role="status"`).

Abaixo das fotos, uma nota: "Logo e cor da faixa você ajusta no estúdio, ao montar o vídeo, sem gastar rodada."

O Criar deixa de mostrar logo, "Remover logo", "Incluir faixa de contato" (checkbox) e "Cor da faixa". O servidor continua aceitando esses parâmetros, sem mudança no `campaign_params`.

**Prévia (coluna da direita):** arco menta (raio 200/200/18/18) com o celular 9:16 inclinado 3 graus e borda creme, a etiqueta "Prévia · 9:16" e o cartão "Suas fotos. / Sua marca no refrão." da landing. Dentro do celular: nome (ou a logo, se a campanha já tiver uma), a oferta e a faixa de contato na cor salva (`cta_background_color`). Sem foto, o fundo é uma arte floresta com a oferta em destaque, no lugar do gradiente cinza com "✳". Atualiza enquanto a pessoa digita, como hoje.

### Passo 2 · Sua música

1. **Ritmo**: tiles em grade (4 colunas no desktop, 2 no celular), um por `Campaign::GENRES`. O rótulo atual é separado em nome e descrição no " · " ("Pop" / "alegre e versátil"). "Escolher por mim" usa um ícone de brilho. Selecionado: fundo floresta, texto creme. O rádio nativo fica visualmente escondido.
2. **Voz**: controle segmentado com as 3 opções de `Campaign::VOCAL_GENDERS`.
3. **Clima**: 3 chips com nome e descrição de `Campaign::STYLES`. Selecionado: fundo lime.
4. **Detalhes do som** (opcional): um botão "+ Detalhes do som" que revela o `textarea` de `music_notes`. Já começa aberto se houver texto.

**Player da marca:** cartão floresta com o nome do ritmo, a descrição, uma onda, o botão tocar/pausar lime, o tempo atual e a duração reais (`timeupdate`) e a nota "Exemplo com voz ilustrativa. Não gasta rodada." Por baixo continua um `<audio preload="none">` com o mesmo `genre-preview` de hoje. Escolher um ritmo troca o exemplo, mas **não toca sozinho**. Sem exemplo para o ritmo (ou "Escolher por mim"), o cartão mostra o texto atual do `genre-preview` no lugar do botão. Erro de reprodução mostra "Não foi possível tocar o exemplo" com "Tentar de novo". No desktop, o cartão ocupa a coluna da direita neste passo. No celular, fica logo abaixo da grade de ritmos.

O cartão também mostra "Sua direção" em chips (ritmo · voz · clima), a partir do resumo que o `campaign-form` já calcula.

### Passo 3 · Conferir e pagar

- Título "Confira e *comece.*" e a frase "Depois do pagamento você revisa a letra e ouve duas versões de música."
- Resumo em três blocos: **Promoção** (oferta, nome e contato), **Som** (ritmo · voz · clima, "Cantada em português do Brasil") e **Fotos** (miniaturas). Cada bloco tem "Editar", que volta ao passo certo. Com o checkout já iniciado (`stripe_session_id` presente), os passos 1 e 2 não existem e o "Editar" some.
- Coluna da direita: cartão de preço floresta como o da landing. "Campanha completa", "PAGAMENTO ÚNICO", o preço em display e o que está incluído (rodadas de `MusicRounds::LIMIT`, ajustes de `lyrics_regen_limit`, vídeo, MP3 e legenda). O botão de pagar fica na barra de ação, não no cartão, para existir um envio só.
- Os avisos de `payment_failed` e de erros de validação aparecem no topo do formulário, com os tokens de atenção, ícone e `role="alert"`.
- Em development, "Testar sem cobrança" continua abaixo do formulário.

### Celular

- Uma coluna, barra de ação fixa no rodapé da tela (respeitando a área segura).
- Nos passos 1 e 3, um botão flutuante "Ver prévia" (com a miniatura da primeira foto) acima da barra de ação. Ele abre um `<dialog>` nativo como folha inferior, com a mesma prévia em arco e o botão "Voltar a preencher". A prévia não aparece mais no fim da página.

### Movimento

- Só `transform` e `opacity`, de 200 a 900 ms, tudo dentro de `@media (prefers-reduced-motion: no-preference)`. O estado base do CSS é o final.
- Título do passo entra com um deslocamento curto ao trocar de passo. A onda do player anima só enquanto toca. Os botões sobem 2 px no hover, como na landing.

### Comportamento do `campaign-form`

O controller atual continua. Os alvos (`step`, `indicator`, `offer`, `business`, `contact`, `photoInput`, `photoList`, `previewOffer`, `soundSummary` etc.) mudam de lugar no HTML, mas mantêm o nome sempre que possível. Entra:

- rolar para o topo ao trocar de passo;
- ir para um passo pelo "Editar";
- trocar placeholder e `inputmode` do contato por opção, e ligar ou desligar `show_cta` pelo chip "Sem faixa";
- preencher o resumo do passo 3;
- abrir e fechar a folha de prévia no celular.

Saem os alvos ligados a logo e cor apenas no Criar. O studio continua usando os mesmos alvos em `_video_appearance`.

## Testes (para o tdd-architect)

- Integração: o Criar renderiza a raiz `.criar` sem `.studio-app`; não tem `input[type=color]` nem o campo de logo; tem os chips de contato com todas as `CTA_OPTIONS` mais "Sem faixa"; preço, limite de fotos e rodadas vêm dos helpers e constantes; `payment_failed` volta com os dados preenchidos; checkout iniciado mostra só o passo 3, sem "Editar".
- Ajustar os testes que procuram o campo de logo ou de cor no Criar (`campaign_branding_test`) para procurá-los no estúdio, onde continuam existindo (`campaign_video_appearance_test`).
- Sistema (`merchant_checkout_test`): percorre os 3 passos; ao avançar do passo 2 o título do passo 3 está visível; "Sem faixa" envia `show_cta=false`; "Editar" volta ao passo; duas escolhas seguidas de fotos somam as duas até o limite e enviam na ordem mostrada; em 390 px, "Ver prévia" abre e fecha a folha.
- A comparação visual com as pranchas e a landing fica com o frontend-analyzer (desktop e 390 px, contraste, foco, `prefers-reduced-motion`).

## Decisões tomadas no design (podem ser revistas na leitura)

1. A seleção de ritmo não toca o exemplo sozinha. No mockup ela tocava; com teclado, cada seta dispararia um som.
2. A landing não muda e não migra para os tokens agora. Ela já tem o visual certo, e mexer nela é risco sem ganho visível.
3. Não há folha de tokens separada: os tokens continuam em `jinglepro.css`, com dois novos.
4. O Criar ganha partials próprios, e o estúdio continua com os de hoje (`_brand_fields`, `_cta_fields`, `_sound_fields`). Dentro de `.creative-studio`, as regras antigas sobrescreveriam os componentes novos. Por isso a duplicação dos campos de contato e de som é temporária, até a fatia 3.
5. O cabeçalho novo vale só no Criar até a fatia 3.
6. O botão de pagar fica na barra de ação, não no cartão de preço.
7. Fotos escolhidas em vezes diferentes se somam, até o limite. Hoje cada escolha substitui todas. Com fotos já salvas no servidor, continua substituindo.
8. Sem arrastar para ordenar: ficam as setas e "Usar primeiro", que já funcionam com teclado. O ícone de arrastar do mockup sai.
9. Os chips de contato usam os textos reais de `Campaign::CTA_OPTIONS` ("Peça pelo WhatsApp", "Venha nos visitar", "Reserve seu horário", "Saiba mais no Instagram"), não os rótulos curtos do mockup. Esse texto entra no briefing da música, então não muda.

## Deixado para quem implementar

- Como mapear o chip "Sem faixa" para `show_cta=false`. Pode ser um atributo virtual em `Campaign` ou JS que mantém um `hidden` de `show_cta`, desde que funcione com o envio normal e tenha teste.
- Nomes e divisão dos partials novos do Criar.
- Conferir quais parciais compartilhados (`_studio_flash`, `_studio_logo`) dependem de `.studio-app` para o estilo e cobri-los em `ui.css` dentro de `.criar`.
- As regras `body .studio-home …` de `jinglepro.css` continuam valendo dentro de `.criar` (por exemplo, `letter-spacing: normal` em `p`, `label` e `button`, e os campos dentro de `.studio-field`). Os componentes novos não usam `.studio-field`, e os títulos dos passos continuam `h2`. Qualquer outro conflito se resolve em `ui.css`, sem `!important`.
- Onde o Rails envolve campos com erro (`field_with_errors`), manter o layout do componente e marcar `aria-invalid`.
- Formato exato da onda do player (barras fixas ou desenhadas a partir do áudio). Barras fixas bastam.
