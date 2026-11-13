# Estúdio da campanha · caminho B (caminho rápido + "Quero mudar algo")

- Data: 13/11/2026
- Tela: estúdio pós-pagamento, hoje em `GET /orders/:order_id/chat` (`order_chat#show` → `order_chat/_campaign_studio`)
- Referências: pranchas `design/jinglepro/Estudio.dc.html`, `Estudio-Mobile.dc.html`, `Entrega.dc.html`; o Criar novo (`docs/superpowers/specs/2026-11-13-criar-caminho-b-design.md`, `app/assets/stylesheets/ui.css`, `app/views/campaigns/new/`)
- Fatia do ROADMAP: 23, fatia 3 (Estúdio em 3 fases)

## Intenção

Depois de pagar, o lojista cai num segundo formulário que repete escolhas que ele já fez no Criar (ritmo, voz, clima em `select`), mistura editar, reescrever e gerar no mesmo bloco, esconde quantas rodadas restam e enterra a duração do vídeo em campos de segundos. O usuário (dono do produto) quer duas coisas ao mesmo tempo:

1. **Quem pagou tem direito de refazer tudo**: letra, som, versões, duração, trecho, fotos e aparência.
2. **Quem não quer refazer nada passa sem esforço**: um caminho simples e didático, em que cada fase tem uma só decisão.

E o visual tem de ser o mesmo do Criar novo e da landing.

## O que o teste real mostrou (13/11/2026, pedido local 71)

- Letra (Mureka lyrics): pronta em < 20 s, US$ 0,009. Veio com `[Outro]` vazio e "a promoção é toda hora", que contradiz "até as 10h". **A revisão da letra não pode ser pulada.**
- Rodada de música (`mureka-9`, `n: 2`): pronta em ~80 s, US$ 0,09. Faixas de 66 s e 163 s, com ~16 s de introdução sem voz apesar do prompt. O trecho sugerido de 30 s já usa `lyrics_sync` (começa em 15,87 s, cobre verso e refrão).
- Problemas de tela vistos: barra de fases "1–2 Letra e música / 3 Vídeo"; "Gerar duas músicas" aprova a letra e gasta a rodada sem dizer; a espera mostra só "Criando duas novas versões…"; o ajuste da próxima rodada some dentro de "Quero ajustar a letra ou a música"; player nativo; "Segundo inicial" mostra `15,870000000000001`; "1 fotos no vídeo"; preparação do vídeo com 4 `<details>`.

## Objetivos

- Três fases claras e nomeadas, como na prancha: **1 Letra · 2 Músicas · 3 Vídeo**, e depois a Entrega.
- Em cada fase, **um** botão principal que leva à próxima com os padrões já escolhidos. Caminho rápido inteiro: 3 cliques (Aprovar letra → Usar esta versão → Gerar meu vídeo).
- Em cada fase, **um** painel "Quero mudar algo" com todas as opções de refazer daquela fase, já preenchidas com o que veio do Criar.
- Rodadas e ajustes sempre visíveis no topo ("Rodadas: 1 de 3 · Ajustes de letra com IA: 20").
- Todo botão que gasta rodada diz isso antes do clique.
- A duração do vídeo vira escolha de primeira linha da fase 3, com o efeito nas fotos visível.
- Mesmo visual e componentes do Criar (`ui.css`, tiles, chips, player da marca, `ui-btn`).

## Fora do escopo

- Limites, preços, modelo e parâmetros da Mureka (`MusicRounds::LIMIT`, `n: 2`, `mureka-9`), a state machine e os jobs.
- Mudar a URL `/orders/:id/chat` ou mover ações de `order_chat#*` (é a fatia 5). O estúdio novo usa as mesmas rotas e ações.
- Biblioteca (`songs#index`), Criar, e-mails.
- Prompt da Mureka (introdução longa e duração). Fica registrado como achado para outra tarefa.

## Anti-objetivos (falhou mesmo que funcione)

- Gastar rodada sem o lojista saber que vai gastar.
- Esconder as opções de refazer a ponto de quem quer refazer não achar.
- Perder versões anteriores ao pedir novas (hoje são guardadas; continua).
- Tocar áudio sem clique.
- Mostrar números fixos ("3 rodadas", "20 ajustes", "28 s", "5 fotos") em vez de constantes e dados reais.

## Restrições

- Valores sempre de `Campaigns::MusicRounds::LIMIT`, `order.lyrics_regen_remaining`, `order.completed_music_rounds`, `Campaigns::PhotoLimit` (`INITIAL`, `MAX`, `SECONDS_PER_PHOTO`, `for_duration`), `asset.track_duration_seconds`, `campaign_price`.
- O estúdio é atualizado por Turbo Streams: `OrderChatBroadcaster` substitui `#chat-lyrics-panel` (`order_chat/_right_panel` → `_campaign_studio`), e `creation-status` faz polling em `order_chat#status` com `creation_version`. O markup novo precisa manter o alvo que o broadcaster substitui (ou o broadcaster é ajustado junto) e o polling.
- `creative-editor` (Stimulus) guarda o estado "ocupado" e as mudanças não salvas; o comportamento (não perder texto digitado quando um broadcast chega, bloquear ações durante geração) continua.
- CSS: só `ui.css`, cores `var(--jp-*)`, sem `!important`; animação só `transform`/`opacity` em `prefers-reduced-motion: no-preference`; foco 3 px, alvos 44 px, texto ≥ 13 px.
- Não mudar `status` direto (AASM). Nenhuma chamada nova de API paga.
- Testes do estúdio existentes continuam valendo no que é comportamento (rotas, ações, limites); seletores de markup migram.

## Caminhos considerados

| | A. Repaginar a página atual | **B. Caminho rápido + "Quero mudar algo" (escolhido)** | C. Piloto automático |
|---|---|---|---|
| O que é | Visual do Criar sobre a mesma estrutura | 3 fases com 1 botão principal; refazer num painel por fase | Gera a 1ª rodada logo após a letra |
| Complexidade para quem não quer mexer | continua | 3 cliques | 2 cliques |
| Direito de refazer | igual a hoje | tudo, num lugar previsível | igual |
| Risco | resolve só a aparência | mais markup e JS novos | gasta rodada com letra possivelmente errada (o teste mostrou letra com erro) |

O usuário escolheu **B** em 13/11/2026, incluindo a duração do vídeo como escolha da fase 3.

## Design

### Casca

- Raiz `div.studio-home.estudio[data-phase="1|2|3|done"]`, sem `studio-app` nem `jp-workspace`, com o cabeçalho compartilhado estilizado como no Criar.
- Topo fixo da página (`ui-head`): nome da campanha, link "Ver dados da campanha", barra de 3 fases (Letra · Músicas · Vídeo; a atual com `aria-current="step"`, as anteriores com marca de feito) e a linha de contadores: "Rodadas: {completed} de {LIMIT} · Ajustes de letra com IA: {lyrics_regen_remaining}".
- A fase vem do servidor, por uma regra única (SPEC 0.4 pede que a derivação status + `video_status` → fase more num lugar só): objeto `Campaigns::StudioPhase` (ou método equivalente) que o estúdio usa e a Biblioteca poderá usar depois.
- Uma fase anterior pode ser revisitada ("← Voltar à letra", "← Voltar às músicas") sem perder nada; isso usa as ações existentes (`change_music` etc.).

### Fase 1 · Letra ("Revise a letra.")

- Estados: preparando a letra (status com texto e animação; pode sair e voltar), letra pronta, falha (mensagem atual e "Tentar preparar a letra novamente").
- Letra pronta: `h2` "Revise a letra.", dica "Confira o nome, o preço e as condições. Editar não gasta rodada.", `textarea` da letra com "Salvar letra" (ou salvamento junto com a aprovação, ver Decisões).
- Botão principal: **"Aprovar letra e ouvir 2 versões"**, com a frase logo abaixo: "Isso usa a rodada {n} de {LIMIT}." (texto da prancha: "Você ainda terá mais duas", calculado).
- "Quero mudar algo" (fechado por padrão):
  - "Pedir para a IA reescrever" (campo do pedido, botão "Reescrever com IA · {N} ajustes"), que usa `order_chat#creation` com `intent=rewrite` ou `regenerate_lyrics`.
  - "Mudar o som": os mesmos tiles de ritmo, voz segmentada e chips de clima do Criar, com o player de exemplo; salvar não gasta rodada.
- Espera da rodada: cartão "Criando duas versões · costuma levar de 1 a 2 minutos. Você pode sair e voltar pela Biblioteca." com animação contida; avisos atuais de `rate_limited`/`status_unavailable` viram linhas desse cartão.

### Fase 2 · Músicas ("Escolha a sua versão.")

- Subtítulo: "Duas versões do mesmo trecho de {duração do trecho}. Ouça até o fim e confira se a oferta ficou completa."
- Dois cartões de versão (A e B) com o **player da marca** (o do Criar: tocar/pausar, onda, tempo, sem `controls` nativo, sem autoplay) tocando a amostra; abaixo, "Música completa {m:ss} · Ouvir completa", que toca a faixa inteira **com marca sonora** no mesmo player. A marca só some depois que a música é aprovada (`approve_music`), como já acontece com `OrderAsset#playback_url` (usuário, 13/11/2026).
- Escolha por rádio nos cartões; botão principal único: **"Usar a Versão {X} e montar o vídeo"** (`select_music`).
- "Quero mudar algo":
  - "Pedir mais duas versões": chips de pedido rápido (ex.: "Mais animada", "Mais calma", "Refrão mais marcante", "Outra voz") + campo livre (`feedback`, 400), mudar som (tiles), editar letra; botão "Criar mais duas versões · usa a rodada {n} de {LIMIT}". Sem rodadas: o painel diz que todas foram usadas e que qualquer versão anterior pode ser escolhida.
- Rodadas anteriores: lista "Rodada 1", "Rodada 2" fechada, com os mesmos cartões e o mesmo botão de escolher.
- Falhas de rodada: texto atual de `_creation_status` ("Esta tentativa não ficou pronta. Ela não consumiu uma rodada.", "Verificar tentativa", "Tentar novamente"), no visual `ui-alert`.

### Fase 3 · Vídeo ("Monte o seu vídeo.")

- Prévia 9:16 no mesmo padrão do Criar (arco + celular), com primeira foto, nome/logo, oferta e faixa.
- **Duração em primeira linha**: chips com as opções que cabem na música, cada uma com o efeito nas fotos: "30 s · ideal para Reels e Status" (padrão), "1 min · até {for_duration(60)} fotos", "1 min 30 · até …", "Música inteira {m:ss} · até …". Ao escolher, o trecho é preparado automaticamente (`excerpt_settings` → preparo local, sem rodada) e o player mostra "Preparando o trecho…" até ficar pronto.
- Fotos: espaços de foto como no Criar, em número igual ao limite da duração escolhida; ao aumentar a duração aparecem os espaços novos ("+{n} espaços liberados"). Salvar fotos não gasta rodada (`video_photos`).
- Botão principal: **"Gerar meu vídeo"** (`approve_music`), desabilitado com motivo visível enquanto o trecho prepara ou se há fotos demais para a duração.
- "Quero mudar algo":
  - "Mudar onde começa": linha do tempo da música com as seções de `lyrics_sync` (verso, refrão) marcadas, posição do trecho arrastável/por teclado, "Ouvir a partir daqui" (toca a prévia completa a partir do ponto); ao confirmar, o trecho do vídeo é preparado (`excerpt_settings`); "Voltar ao trecho sugerido".
  - "Duração exata": um campo `mm:ss` (substitui o par `select` "Personalizar" + campo de segundos).
  - "Aparência do vídeo": logo, cor da faixa e faixa de contato (`_brand_fields`/`_cta_fields`, restilizados ou reescritos; o Criar não os mostra mais).
- Montando o vídeo: checklist da prancha ("✓ Música escolhida · trecho de {d}", "Montando o vídeo com as fotos e a oferta", "Pronto para baixar e postar"), "Ir para minhas campanhas".
- Entrega (`campaigns/_delivery`): reskin conforme a prancha `Entrega`, se couber no mesmo PR; senão, próximo PR (ver Decisões).

### Correções que vão junto

- Formatar segundos (`15,870000000000001` → `0:15,9` ou `m:ss`) em todo lugar do estúdio.
- Pluralização ("1 foto", "2 fotos").
- Nenhum texto com número fixo.

### Celular

- Mesmo conteúdo em uma coluna; barra de ação fixa embaixo com o botão principal da fase; contadores numa linha abaixo das fases; prévia em folha ("Ver prévia"), como no Criar. A prancha `Estudio-Mobile` cobre a fase 2; as fases 1 e 3 seguem o mesmo padrão.

## Decisões

1. Caminho B, com a duração como escolha principal da fase 3 (usuário, 13/11/2026).
2. Rotas e ações de `order_chat#*` não mudam; só views, CSS e JS, exceto a prévia completa (Decisão 11) (minha decisão, para não misturar com a fatia 5).
3. Raiz `.estudio` e componentes em `ui.css`; a guarda de CSS passa a aceitar `.criar`, `.estudio` ou `.ui-` (minha decisão).
4. Os tiles/chips/player do Criar viram partials compartilhadas (`app/views/shared/ui/` ou parecido) em vez de copiadas (minha decisão; o construtor escolhe o nome).
5. Aprovar a letra salva o texto editado antes (como `CreationChanges` já faz com `intent=generate`), para o lojista não perder edição ao aprovar (minha decisão).
6. Preparar o trecho automaticamente ao trocar a duração (minha decisão: é local e grátis; o construtor confirma que não enfileira trabalho duplicado em cliques seguidos).
7. A Entrega entra se o PR não ficar grande demais; o construtor decide e diz no plano.
8. "Montando o vídeo", falha do vídeo e Entrega continuam em `/campaigns/:id` (`campaigns/show`, polling `campaigns#status`, alvo `#campaign-delivery`); o redirect de `approve_music` não muda. `campaigns/show` ganha a mesma casca `.estudio` e a barra de fases, com a fase 3 em "montando"/"falhou" e depois "Entrega" (minha decisão, após a revisão: evita mexer em controller e mantém a Decisão 2).
9. Não há fase revisitada no cliente: a fase sempre vem do servidor. "← Voltar à letra" na fase 2 abre o "Quero mudar algo" da fase 2 já no item "Editar letra"; "← Voltar às músicas" na fase 3 é `change_music` (minha decisão, após a revisão: evita estado de fase no cliente que o broadcaster apagaria e um segundo caminho para gastar rodada).
10. Enquanto o trecho prepara, os chips de duração e a linha do tempo ficam bloqueados (`ExcerptSettings` já recusa com `:preview_busy`).
11. Cada versão tem uma prévia da música inteira com marca sonora, ouvível já na fase 2; sem marca só depois da aprovação (usuário, 13/11/2026). Isso é a única exceção à Decisão 2 e pede backend:
    - renderizar a prévia completa com `Campaigns::AudioAudition.render(start_seconds: 0, duration_seconds: track_duration_seconds)` num job (ao ficar pronta a rodada, ou sob demanda no primeiro "Ouvir completa"), guardada à parte do trecho do vídeo, para não trocar o trecho escolhido;
    - servida pelo mesmo caminho autenticado de `campaign_audio#preview` (dono da campanha), nunca a URL do arquivo original da Mureka;
    - passa pelo `security-engineer` (áudio inteiro exposto antes da aprovação; a marca sonora tem de cobrir a faixa toda);
    - "Ouvir a partir daqui" na linha do tempo da fase 3 usa essa prévia completa (pula para o ponto), sem preparar trecho novo a cada posição.

## O que fica para quem constrói

- Nomes de partials, alvos Stimulus e como dividir `creative-editor`.
- Se o "Salvar letra" continua como botão separado ou vira salvamento ao sair do campo.
- O desenho exato da linha do tempo do trecho (acessível por teclado, com `aria-valuetext` em m:ss).
- Ordem das tarefas e cortes de PR.

## Testes esperados (resumo)

- Integração: fase derivada por status + `video_status` (todas as linhas da tabela do SPEC 0.4 que caem no estúdio); contadores; botão principal único por fase e texto de consumo de rodada; painel "Quero mudar algo" com as opções certas por fase; sem rodadas restantes; durações oferecidas só até a duração da música; limite de fotos por duração; sem números fixos; nenhum `select` nem `audio[controls]` no estúdio.
- Sistema: caminho rápido em 3 cliques com Mureka stubada (WebMock), pedido de mais versões, voltar de fase sem perder edição, troca de duração preparando o trecho, nenhum áudio sem clique, celular sem rolagem horizontal.
- Os testes atuais do estúdio (`campaign_guided_studio_test`, `campaign_creative_flow_test`, `campaign_video_appearance_test`, `campaign_video_personalization_test`, `campaign_sound_settings_test`) migram seletores e continuam afirmando o comportamento.
