# Design JinglePro (referência de design)

Redesign da JinglePro desenhado num canvas de design e exportado para cá em 09/11/2026. Substitui o antigo `Plataforma - Vanilla.html` como referência visual.

## Como ler estes arquivos

- Cada `*.dc.html` é uma prancha. O HTML e o CSS são normais e servem de referência direta. O `<script type="text/x-dc">` no fim só descreve estado e interações do protótipo; não é código do app.
- As pranchas **não abrem sozinhas no navegador**: dependem do `support.js` do canvas e de imagens `/_blob/...` que não estão aqui. Para ver o layout, abra o canvas original ou use os PNGs (pendentes, ver "Pendências").
- `canvas.json` guarda a posição e o tamanho de cada prancha. `assets/` tem as duas fotos usadas nos exemplos (pizza e café).
- Reproduzir **tokens, proporções, estados e movimento**. Adaptar a sintaxe para ERB + CSS do app + Stimulus.

## Pranchas e telas do app

| Prancha | Tela do app (alvo) | Fatia |
|---|---|---|
| `Diagnostico` | Auditoria do design anterior, checklist do 4.9 e sistema de design | n/a |
| `Main`, `Landing-Mobile` | `pages/home` | 1 |
| `Entrar` | `users/sessions/new` e telas de senha | 1 |
| `Biblioteca` | `songs/index` | 1 |
| `Estados` | vazio, erro de preenchimento, confirmando pagamento, falha do vídeo, letra que não saiu, recuperar senha | 1 a 3 |
| `Criar`, `Criar-Mobile` | `campaigns/new` (3 passos) | 2 e 4 |
| `Estudio`, `Estudio-Mobile` | estúdio em 3 fases: letra, músicas, vídeo | 3 |
| `Entrega` | `campaigns/_delivery` | 3 |

Ainda **não desenhados**: mobile dos passos 2 e 3 do Criar, mobile das fases 1 e 3 do Estúdio, e-mail já cadastrado no passo 3, consentimento junto ao botão "Pagar" e o estado "Precisa de atenção" da Biblioteca.

## Tokens

| Token | Valor | Uso e contraste |
|---|---|---|
| Floresta | `#173E32` | texto e botões; 10,8:1 sobre creme |
| Apoio | `#4C6155` | texto secundário; 6,1:1 sobre creme, 5,4:1 sobre menta |
| Borda de campo | `#6F8577` | campos de formulário; 3,9:1 sobre a superfície |
| Lime | `#D6F36B` | **só como fundo**, nunca como texto sobre creme; 9,5:1 com floresta |
| Menta | `#E5EADC` | fundo de seção e chips |
| Creme | `#F6F5ED` | fundo da página |
| Superfície | `#FFFEF9` | cartões e campos |
| Borda de cartão | `#CFD8C9` | divisórias e cartões |
| Link/hover | `#24593E` | hover de links |
| Atenção/erro | `#9A3412` sobre `#FFF0E7`, borda `#D9A784` | erros e estados de falha; 6,6:1 |

Não escrever cores à mão no CSS do app: tudo vira variável CSS (`--jp-*`).

## Tipografia

- **Manrope** 400 a 800 para tudo. **Cormorant Garamond** itálico 600 em **uma** palavra de título, só de 40 px para cima e nunca na interface.
- Escala: display 76 (entrelinha 1,02), título 52, subtítulo 26, corpo 16 a 20, rótulo 14 a 15, microtexto 13 (**piso**).

## Componentes

- Botões em pílula de 52 a 64 px. Campos de 56 px com borda de 1,5 px. Cartões com raio de 24 px.
- Alvos de toque de pelo menos 44 px. Foco visível de 3 px em floresta, com deslocamento de 3 px.
- Ícones SVG com `aria-hidden`; nada de glifos como "↗" dentro do texto dos botões.
- Escolhas (ritmo, voz, clima) com radios nativos estilizados, não `button aria-pressed`.
- Campos com `label` real. Erros com texto e ícone (não só cor), `aria-invalid` e anúncio por `role="alert"`.
- Pontos de quebra: 640, 960 e 1280, mobile-first.

## Movimento

Uma ideia só: "o som vira imagem".

- Apenas `transform` e `opacity`, de 200 a 900 ms.
- O estado base do CSS **é o estado final**; a animação parte dele. Assim `prefers-reduced-motion` e navegadores sem suporte mostram o resultado completo.
- Toda animação fica dentro de `@media (prefers-reduced-motion: no-preference)`.
- Loops têm controle de pausa. No protótipo é a classe `.jp-paused`; no app deve ser `[data-motion="off"]`, sem `!important`.
- Revelar ao rolar usa `animation-timeline: view()` dentro de `@supports`. No Firefox o conteúdo simplesmente aparece sem animação.
- Reiniciar uma animação: alternar entre dois nomes de keyframe ou de classe.
- O preenchimento do player de áudio no protótipo é CSS fixo (28 s); no app deve seguir `timeupdate` do áudio real.

## Textos e números que não podem ser fixos

O protótipo escreve "R$ 79", "3 rodadas", "20 ajustes" e "28 s" no texto. No app esses valores vêm de: `campaign_price`, `Campaigns::MusicRounds::LIMIT`, `config/brands.yml` (`tiers.starter.lyrics_regen_limit`) da duração escolhida do vídeo (`Campaigns::AudioPreview::DEFAULT_DURATION` como padrão, até a música inteira) e do limite proporcional de fotos (`Campaigns::PhotoLimit`). As cinco fotos da prancha são a seleção inicial; no estúdio, vídeos mais longos liberam mais fotos, até trinta.

## Pendências

- PNGs de cada prancha (1440 e 390 px), exportados do canvas.
- O canvas nunca foi aberto em Chrome, Safari, Firefox nem num celular. A estimativa do desenho é perto de 4,5; o 4,9 depende de conferir em navegador real, testar com 3 a 5 lojistas e comparar o app implementado com Playwright.
