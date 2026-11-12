# ViraJingle

Plataforma que transforma a promoção de um negócio em uma **campanha** pronta
para postar: música cantada, vídeo vertical 9:16 (MP4), MP3 e legenda. Produto
único, em português (pt-BR) e BRL, por R$ 29,90 em pagamento único (o valor vem de
`config/brands.yml` e de `campaign_price`). Rails 8.1, Ruby 4.0.5, PostgreSQL,
Hotwire, CSS próprio e Tailwind CSS 4.

Onde ler mais:

- `SPEC.md`, seção 0: o produto atual, os limites e o mapeamento de estados (pedido → fase do estúdio → Biblioteca). As demais seções do SPEC são do app anterior e estão marcadas como LEGADO onde divergem do código.
- `CLAUDE.md`: stack conferida, convenções e fluxo de trabalho com agentes.
- `ROADMAP.md`: andamento, inclusive o redesign JinglePro (fatias 0 a 5).
- `design/jinglepro/README.md`: referência de design (ver "Referência de design" abaixo).

## Desenvolvimento local

Com Ruby e PostgreSQL disponíveis:

```sh
bundle install
# Em um checkout novo, copie .env.example para .env e configure as integrações.
# Preserve o .env existente ao retomar o projeto.
bin/rails db:prepare
bin/rails server -b 127.0.0.1 -p 3000
```

Se aplicar migrações enquanto o servidor local já estiver rodando, execute
`bin/rails restart` em seguida. O processo precisa recarregar a estrutura do
banco para persistir corretamente os campos novos.

Abra [ViraJingle local](http://127.0.0.1:3000). Para alterações nas classes
Tailwind, rode `bin/css` em outro terminal. O `bin/dev` também inicia o Stripe
CLI conforme `Procfile.dev`. O processo de estilos permanece ativo mesmo sem
entrada de terminal. Se o executável nativo falhar neste computador, `bin/css`
prepara automaticamente a CLI oficial Node da mesma versão em
`tmp/tailwindcss-cli` (precisa de Node.js/npm e internet na primeira preparação).
`bin/css --build` faz uma compilação única. Configurações explícitas em
`TAILWINDCSS_INSTALL_DIR` são preservadas. O build Linux de produção continua
usando o compilador nativo.

O layout carrega, em todas as páginas, todo CSS de `app/assets/` (`stylesheet_link_tag :app`):
os estilos escritos à mão em `app/assets/stylesheets/` (`landing.css`, `studio.css`,
`studio_app.css`, `studio_identity.css`, servidos pelo Propshaft sem compilação) e o
Tailwind compilado em `app/assets/builds/tailwind.css`. Os componentes compartilhados
ficam em `app/views/shared/`. A fatia 1 do redesign (ver ROADMAP) unifica o CSS.

## Preparação para produção

O deploy usa Kamal com HTTPS, um domínio exato em `APP_HOST`, quatro bancos
PostgreSQL e um volume persistente para fotos, músicas e vídeos. Sem as variáveis
obrigatórias, o app recusa iniciar e informa os nomes que faltam, sem imprimir
credenciais. O build de assets usa `SECRET_KEY_BASE_DUMMY=1` e dispensa essas
credenciais; essa variável **não deve ser definida no servidor em execução**.

1. Registre um domínio e aponte o subdomínio do app para o servidor. Ainda não há
   um domínio real definido para este projeto; os endereços dos exemplos não são nossos.
2. Copie `.env.production.example` para `.env.production` (ignorado pelo Git).
   Configure os quatro bancos distintos, a chave mestra de produção, Stripe,
   Mureka, Resend, servidor SSH e acesso ao GitHub Container Registry.
   O usuário dos bancos precisa poder executar as migrações. Em produção,
   `.env` não é carregado automaticamente pelo Rails.
3. Carregue essas variáveis no terminal ou gerenciador de segredos usado pelo
   Kamal. Não cole chaves em chats nem as versione. O `.kamal/secrets` lê o
   ambiente; não escolhe automaticamente a chave de desenvolvimento.
4. Execute `bin/kamal setup` no primeiro deploy e `bin/kamal deploy` nos seguintes.
   Não execute esses comandos até configurar o servidor e DNS reais. O Kamal
   termina TLS e define `BEHIND_SSL_PROXY=true`; use essa opção somente atrás de
   um proxy confiável com HTTPS. Fora desse modo, o Rails redireciona HTTP para HTTPS.
5. Configure na Stripe o endpoint `https://APP_HOST/stripe/webhook` para
   `checkout.session.completed`, `payment_intent.payment_failed` e `charge.refunded`.
   Use o segredo de assinatura desse endpoint. Teste primeiro com as chaves de teste.

O supervisor Solid Queue roda junto ao Puma nesse deploy inicial. Além das filas
de geração, há um worker para `webhooks`; eventos que falham têm cinco tentativas,
depois ficam `failed` para revisão. O scheduler consulta músicas pendentes e
recupera letras/vídeos interrompidos. Após 30 minutos sem atualização, uma letra
já salva ou um vídeo já anexado é recuperado; caso contrário, a etapa volta a
permitir tentativa manual. Chamadas de IA já iniciadas não são reenviadas
automaticamente, pois podem ter sido cobradas. Pagamentos salvos antes de uma
falha de enfileiramento e vídeos aprovados ainda não enfileirados também são retomados.
O mesmo vale para a primeira reserva musical e para o arquivamento/preparo de
áudio interrompidos: estes retomam os arquivos existentes, sem gerar novas músicas.

Preencha `SENTRY_DSN` e configure alertas no projeto Sentry para falhas de geração
e esgotamento de tentativas de pagamento. Sem DSN, continuam apenas os logs locais.

### E-mails gratuitos com Resend

Em 11/11/2026, o [plano Free da Resend](https://resend.com/pricing) oferece
3.000 e-mails por mês, com limite de 100 por dia. A integração usa SMTP com
STARTTLS obrigatório e validação do certificado; não exige uma gem adicional.

1. Crie uma conta gratuita na Resend e uma chave com permissão de envio.
2. Depois de registrar seu domínio, adicione-o no painel da Resend e publique os
   registros DNS de autenticação indicados por ela. Aguarde a verificação.
3. Defina `RESEND_API_KEY`, `MAILER_FROM` (apenas o endereço, por exemplo
   `avisos@virajingle.com.br`) e `APP_HOST` (sem `https://` nem caminho).
   O remetente é compartilhado pelo app e pelo Devise; os links de recuperação
   de senha usam sempre o domínio configurado e HTTPS.
4. Valide a recuperação de senha e a entrega na caixa de entrada com uma conta
   sua antes de liberar o cadastro. Desative rastreamento de cliques para e-mails
   de autenticação no painel do provedor.

Sem domínio, a Resend permite testes com `onboarding@resend.dev` **somente para
o endereço da própria conta Resend**. Isso não habilita envio para clientes.
Nenhuma credencial Resend é versionada. Para ativar envios reais em desenvolvimento,
defina `MAIL_DELIVERY_METHOD=resend`, `RESEND_API_KEY` e
`MAILER_FROM=avisos@virajingle.com.br` no `.env` e reinicie o app. O nome exibido é
`ViraJingle`; os links locais continuam apontando para `localhost:3000`.
Sem a opção de envio, desenvolvimento conserva SMTP local. Testes usam sempre a
caixa de saída em memória, mesmo que o `.env` contenha uma chave e essa opção.
Em produção, o envio já está habilitado e as variáveis precisam ser fornecidas
pelo ambiente de deploy; o Rails não lê o `.env` automaticamente.

Referências: [SMTP](https://resend.com/docs/send-with-smtp),
[domínio verificado](https://resend.com/docs/dashboard/domains/introduction) e
[limite do remetente de teste](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain).

### Backup e validação antes da abertura

O volume `music_ai_gen_storage` conserva os arquivos entre deploys; ele não
protege contra perda do servidor. Configure snapshots/dumps dos quatro bancos e
cópia do volume **fora do servidor**, com acesso restrito e retenção definida.
Pare os workers e as gravações durante uma cópia coordenada de banco + arquivos.
Teste a restauração desses bancos e do volume em uma instalação isolada e confira
login, biblioteca e downloads. A rotina real de backup e esse teste dependem da
infraestrutura escolhida; não estão ativados só por existir um volume no deploy.

Antes de abrir para clientes: valide `GET /up`, redirecionamento HTTP, envio e
recuperação de senha, webhook após fechar a aba de pagamento, geração com foto,
aprovação, MP3/MP4, reinício dos workers e restauração de backup. Execute
`bin/rails test`, `bin/rails test:system`, `bin/rubocop`, `bin/brakeman` e os
audits de dependências. O CI instala também FFmpeg, ImageMagick, `rsvg-convert` e fontes para
exercitar os testes reais de processamento de mídia.

O CI também constrói a imagem de produção e executa um teste de inicialização e
renderização de MP4 com três fotos artificiais (JPG/PNG/WebP), sem banco ou APIs:

```sh
docker build -t music_ai_gen:production-check .
docker run --rm --entrypoint /rails/bin/rails -e SECRET_KEY_BASE_DUMMY=1 music_ai_gen:production-check runner script/production_smoke.rb
```

## Referência de design

O design vive em `design/jinglepro/`, exportado de um canvas de design em 09/11/2026,
e substitui o antigo `Plataforma - Vanilla.html`. São pranchas `*.dc.html` (HTML e CSS
estáticos), `canvas.json` e um `README.md` com o mapa prancha → tela do app, os tokens
(`--jp-*`), a tipografia, os componentes e as regras de movimento. As pranchas não abrem
sozinhas no navegador: dependem do `support.js` do canvas e de imagens que não estão no
repositório. Leia `design/jinglepro/README.md` antes de mexer em qualquer tela.

## Testes

```sh
bin/rails test
```

Se o executável nativo do Tailwind encerrar com `SIGKILL` durante
`test:prepare`, é possível verificar a suíte Ruby separadamente:

```sh
bundle exec ruby -Itest -e 'Dir.glob("test/**/*_test.rb").sort.each { |file| require_relative file }'
```

Esse comando não valida a compilação do CSS. Os testes usam o banco
`music_ai_gen_test` e simulam as APIs externas com WebMock.

Para compilar também o CSS nesse Mac, há uma alternativa oficial ao executável
nativo, sem mudar o projeto nem o build Linux:

```sh
npm install --prefix tmp/tailwindcss-cli --no-save @tailwindcss/cli@4.3.0 tailwindcss@4.3.0
NODE_PATH="$PWD/tmp/tailwindcss-cli/node_modules" TAILWINDCSS_INSTALL_DIR="$PWD/tmp/tailwindcss-cli/node_modules/.bin" bin/rails test
```

As mesmas duas variáveis funcionam com `bin/rails test:system` e
`RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile`.
O mecanismo `TAILWINDCSS_INSTALL_DIR` é suportado pela gem; o compilador Node
foi usado para validar o build local quando o binário macOS encerrou com SIGKILL.

## Estado ao retomar

- Preços e limites efetivos estão em `config/brands.yml` (campanha: tier `starter`, R$ 29,90). Os valores em € das seções antigas do SPEC (1 a 4 e 18) são LEGADO; a seção 0 do SPEC está alinhada com o YAML.
- O fluxo atual cria o pedido em `pending` (`POST /campaigns`) e cobra pelo Stripe Checkout (`POST /orders/:id/checkout`). O pagamento é confirmado pelo webhook `/stripe/webhook` ou pela reconciliação em `GET /campaigns/:id`. Cobrança real com chaves de produção não foi exercitada (a confirmar antes do primeiro deploy).
- Em 08/11/2026, o fluxo vocal foi validado com APIs reais: chat → letra Mureka → aprovação → duas músicas → reprodução → escolha da variante B → biblioteca e download. Projeto local: `ORD-2026-JKCJF` (`/orders/46/chat`). As variantes tiveram 41,79 s e 35,75 s para um briefing de 30 s; a duração pedida ainda é uma orientação ao provedor.
- A suíte Ruby passou com 907 testes e 1.700 assertions após as correções (registro de 08/11/2026; não reexecutado ao revisar a documentação, a confirmar). Pagamentos, soundtrack e regeneração musical não foram exercitados com APIs reais nesta rodada.
- Home, autenticação, estúdio e biblioteca compartilham o visual de estúdio. O estúdio ainda é a tela `/orders/:id/chat` (herança do chat conversacional, hoje LEGADO); no celular ela alterna entre conversa e painel de texto/música. O redesign JinglePro o reorganiza em 3 fases (letra, músicas, vídeo): ver ROADMAP, fatias 3 e 5.

### Campanhas para o Brasil

A entrada principal agora oferece uma campanha por R$ 29,90 (valor em `config/brands.yml`), em BRL: briefing guiado → resumo → Stripe Checkout → letra → escolha musical → MP4 vertical e legenda. Pedidos antigos conservam sua moeda. `GET /orders/new` não cria nem paga pedidos.

Execute `bin/rails db:migrate`. O renderizador precisa de FFmpeg/ffprobe e ImageMagick (`magick` ou `convert`), além de Arial no macOS ou DejaVu Sans no Linux. O Dockerfile instala as dependências Linux. Pode-se definir `IMAGEMAGICK_BIN`. O vídeo usa a música aprovada, foto opcional e os dados da campanha; fica salvo via Active Storage. Produção precisa de armazenamento persistente e workers ativos.

Configure `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET`. O webhook de confirmação deve chegar a `/stripe/webhook`; visitar a URL de sucesso não confirma pagamento. O botão “Testar sem cobrança” só existe em development e não está disponível em produção. A geração musical consome a API real, inclusive neste teste local.

### Revisões e histórico de campanhas — 09/11/2026

Campanhas incluem três rodadas completas de duas versões. A letra pode ser editada manualmente sem consumir rodadas; até 20 reescritas por IA são incluídas. Cada edição cria um novo `LyricsDraft`. O cliente pode guardar uma favorita e aprovar uma versão de qualquer rodada. A aprovação usa o ID do arquivo e sua geração/letra originais, inclusive ao montar o vídeo.

`Campaigns::MusicRounds` reserva cada tentativa sob lock antes de enfileirar `GenerateCampaignMusicJob`. `PollCampaignMusicJob` só contabiliza uma rodada quando recebe duas músicas válidas. Falhas não consomem rodadas; o retry reutiliza a direção musical da tentativa e a letra salva mais recente. Sem edição posterior, o pedido é idêntico. Jobs duplicados não submetem a mesma tentativa novamente. Os MP3 de cada rodada são arquivados por `ArchiveCampaignAudioJob`; os links do provedor são usados enquanto o arquivo não está disponível localmente. Produção precisa de workers e Active Storage persistentes, com backup. Monitorar falhas de arquivamento; não apagar arquivos de versões favoritas/anteriores.

As mudanças musicais são novas interpretações da letra salva, com a direção anterior e o pedido explícito de alteração. Não são remix/edição precisa do áudio. A interface informa isso. O modelo de campanhas é fixado em `Campaigns::MusicRounds::MODEL = "mureka-9"`, com `n: 2`, inclusive nas novas tentativas após falha. Não há seleção por variável de ambiente.

O formulário oferece dez ritmos, voz feminina/masculina/automática, clima e até 240 caracteres de direção adicional. As escolhas ficam salvas na campanha e podem ser revistas no estúdio antes de cada rodada disponível, sem gastar geração. `gender` é enviado no campo próprio da API; a escolha automática omite o campo. Ritmo, instrumentos e interpretação são descritos no prompt, sem garantia de reprodução exata. Cada tentativa registra um snapshot de `sound_settings`; mudanças posteriores não alteram favoritas nem versões antigas. Alterar os controles descarta a direção textual anterior ao montar a nova tentativa, evitando conflitos com escolhas antigas. Tentativas após falha também respeitam as preferências recém-salvas.

A Mureka documenta referência de áudio via upload (`purpose: reference`, MP3/M4A, trecho de 30s) e `reference_id`, além de clonagem vocal separada via `vocal_id`. Esses uploads e clonagem não estão expostos no produto. O campo de detalhes é uma orientação textual, não upload/reprodução de uma música ou voz de cantor. Documentação: [geração](https://platform.mureka.ai/docs/api/operations/post-v1-song-generate.html), [uploads](https://platform.mureka.ai/docs/api/operations/post-v1-files-upload.html).

O seletor de ritmos tem exemplos cantados de 12 segundos, gerados uma vez com o V9 e uma letra própria comum ao catálogo. São arquivos MP3 em `public/demos/genres`, com origem, tarefa, prompt, duração e custo estimado em `config/genre_samples.json`. Apenas arquivos marcados como prontos aparecem no player. Ouvir exemplos não invoca APIs nem consome rodadas; há apenas o tráfego normal de arquivos estáticos. A voz da amostra é ilustrativa, não uma prévia personalizada. O player não toca automaticamente e interrompe o exemplo ao trocar de ritmo ou etapa.

Para preparar uma amostra ausente, em desenvolvimento: `SAMPLE_GENRE=forro bin/rails runner script/generate_genre_sample.rb`. Execute uma por vez. A ferramenta reutiliza tarefas pendentes e não repete solicitações com resultado incerto; confira a conta do provedor antes de autorizar uma nova tentativa. O custo de criação do catálogo é separado do custo por campanha.

O botão “Salvar o som do meu negócio” guarda uma `BusinessMusicProfile` por usuário e nome de negócio normalizado. O cliente escolhe explicitamente essa identidade ao criar outra campanha; apenas nome e preferências musicais são preenchidos. Ofertas, contatos, fotos e preços não são copiados. Alterações numa campanha não sobrescrevem a identidade sem o botão de atualização. Depois da aprovação, salvar usa o snapshot da versão escolhida, inclusive quando a favorita pertence a uma rodada antiga. A identidade guarda direção musical, não uma voz clonada nem uma melodia fixa.

Cada versão começa com uma prévia de até 30 segundos, preparada por `PrepareCampaignAudioJob` após arquivar o MP3 original. Antes de aprovar, o cliente pode escolher 30 segundos, 1 minuto, 1min30, a música inteira ou uma duração personalizada até o fim da faixa. O player principal reproduz esse trecho com fade de saída; a aprovação só libera quando ele estiver pronto. O vídeo copia o áudio AAC aprovado sem recortar ou aplicar um segundo fade. A música completa continua disponível num player secundário. Campanhas antigas já aprovadas preservam a montagem anterior; versões antigas ainda não aprovadas têm um botão para preparar o trecho. Uma falha no preparo permite tentar novamente sem chamar a Mureka nem consumir rodada.

A [documentação oficial de geração](https://platform.mureka.ai/docs/api/operations/post-v1-song-generate.html), incluindo o schema publicado em seu bundle, anuncia `duration` apenas para V9.5 e no intervalo de 120–300 segundos. Não enviamos `duration: 30`, que não é suportado, nem prometemos que a música original terá 30 segundos. O controle do anúncio é local; o cliente deve conferir se a oferta está completa no trecho antes de aprovar. `audio_preview_seconds` no relatório mede o processamento dessas prévias, separado da renderização do vídeo; o custo monetário da infraestrutura depende do ambiente.

### Chat, recuperação e escolha do trecho

Pedidos de ritmo, voz, clima e instrumentos no chat passam pela mesma validação dos controles visíveis e atualizam a campanha e o briefing. A resposta da IA fornece somente as mudanças solicitadas; confirmações preservam as escolhas atuais. Uma resposta atrasada não sobrescreve controles ou letra alterados enquanto o chat respondia, nem dispara outra geração. O histórico de músicas conserva os snapshots originais.

`GenerateCampaignMusicJob` registra a submissão antes de chamar a Mureka. Uma tarefa com ID salvo é retomada somente por consulta, sem novo POST. Erros transitórios de consulta aguardam até 30 minutos; depois, “Verificar tentativa” consulta o mesmo ID e pode recuperar o resultado. Timeout de submissão ou resposta ambígua não autoriza reenvio automático. HTTP 429 por concorrência tem até três envios com espera; falta de créditos e requisições rejeitadas exigem revisão. Há um teto técnico de cinco pares potencialmente cobrados e doze envios por campanha, separado das três rodadas completas oferecidas ao cliente. Ao atingir o teto, as músicas anteriores continuam disponíveis, mas novas gerações exigem revisão operacional. Estimativas incertas continuam na conta; rejeições explícitas sem tarefa aceita são registradas com estimativa zero.

`RecoverCampaignMusicJob` recupera tarefas interrompidas e está agendado a cada minuto em `config/recurring.yml` (somente no bloco `production`). Produção precisa executar o scheduler e os workers do Solid Queue. Em desenvolvimento, a consulta de status da página também solicita recuperação de tarefas paradas. Execute a migração `20261109160000` antes de iniciar os workers atualizados.

Cada música preparada permite escolher a duração e ajustar o início do vídeo por um controle deslizante ou pelo segundo inicial. A opção “Música inteira” usa a gravação desde o início; a sugestão automática restaura o corte curto. “Preparar e ouvir este trecho” produz uma prévia local da duração escolhida, com fade; não chama a Mureka nem consome rodada. O original permanece intacto. A aprovação inclui a revisão do corte, impedindo que uma aba antiga aprove um áudio que mudou. O MP4 copia os mesmos pacotes AAC da prévia aprovada, sem novo corte ou codificação. Cortes só podem mudar antes da aprovação. A migração `20261111220000` adiciona `excerpt_duration_seconds` (padrão 30; `nil` significa música inteira) e `video_revision` para a composição. O renderer distribui as fotos por toda a duração e ajusta o prazo de processamento para vídeos longos.

Na fase de escolha musical, o cliente também pode adicionar, remover e reordenar as fotos. O limite acompanha a duração: cinco fotos até 30 s, dez em 1 min, quinze em 1min30, vinte em 2 min e no máximo trinta. `Campaigns::PhotoLimit` calcula a proporção de uma foto por seis segundos, usando a duração arredondada ao segundo (como na interface), com piso de cinco. A entrada inicial continua com até cinco fotos; mais fotos são incluídas no estúdio após preparar uma versão mais longa. O editor libera o maior limite entre as versões disponíveis. Cada aprovação e renderização confere o limite da versão escolhida; escolher um corte menor preserva as fotos e pede ajuste antes de aprovar. Novos arquivos podem ser misturados às fotos salvas; IDs de outras campanhas e seleções inválidas são rejeitados. A aprovação confere a revisão das fotos e do áudio sob o mesmo lock do pedido. O vídeo aprovado permanece imutável. Essas edições não chamam a API musical nem gastam rodadas; vídeos mais longos exigem mais processamento e armazenamento locais.

As quebras de linha da oferta são preservadas na prévia, nas telas de revisão e na arte/vídeo. O símbolo `R$` fica junto do valor durante a quebra automática. A faixa de contato é opcional desde a criação e pode mudar na fase musical, antes da aprovação, inclusive sua cor de fundo; o texto recebe uma cor com contraste adequado. Desativá-la dispensa contato e chamada, remove a faixa inteira da arte e do MP4 e omite o contato da legenda sugerida. Alterações no estúdio afetam só a composição visual, incrementam `video_revision` e não geram outra música. Execute a migração `20261112010000` para adicionar `show_cta` (padrão `true`) e `cta_color` (padrão `#d6f36b`). Campanhas já aprovadas não mudam.

O nome do negócio também é opcional. É possível enviar uma logo independente das fotos (PNG, JPG ou WebP de até 5 MB), usar nome e logo juntos ou omitir ambos. A logo preserva proporção e transparência no cabeçalho da arte e do vídeo. Nome, troca e remoção da logo ficam em “Aparência do vídeo” no estúdio, sob a mesma revisão da composição e antes da aprovação; essas alterações não mudam a música já criada. Uma campanha sem nome mantém a oferta e não pede à IA para inventar uma empresa. A logo usa os anexos do Active Storage existentes, sem nova migração.

### Medição de custo por campanha

`GenerationCost` registra cada chamada de letra, cada tentativa musical e cada chamada do chat (incluindo retries), além do tempo de parede e tamanho do vídeo. Valores são **estimativas de API**, não conciliação de fatura nem lucro líquido. A taxa `COST_USD_BRL` (padrão 6) e a versão de preços são gravadas por evento; mudar a configuração não recalcula o passado.

```sh
bin/rails campaigns:costs > tmp/campaign-costs.csv
CAMPAIGN_ID=123 bin/rails campaigns:costs > tmp/campaign-123-costs.csv
```

O CSV separa custo estimado total, parcela incerta, chamadas sem preço, segundos de renderização e tentativas musicais antigas sem registro. `uncertain_api_brl` já está incluído no total — não somar novamente. Falha/timeout não comprova devolução pela Mureka: mantemos a estimativa incerta para conciliação. Renderização local mede tempo, mas não inventa um preço por segundo: servidor, armazenamento acumulado, pagamentos, tributos, atendimento e CAC devem ser acrescentados à análise financeira. Campanhas anteriores à instrumentação têm cobertura parcial; zero eventos não significa custo histórico zero.

Preços usados em 09/11/2026: [Mureka API](https://platform.mureka.ai/pricing) (letra US$ 0,009; música V9 US$ 0,045/unidade, V9.5 US$ 0,15/unidade) e [GPT-4o mini](https://developers.openai.com/api/docs/models/gpt-4o-mini) (US$ 0,15/0,075/0,60 por milhão de tokens de entrada/cache/saída). O modelo de chat existente foi preservado. Rever a tabela quando o provedor alterar preços.

O preço publicado é R$ 29,90 por campanha completa, em pagamento único e sem assinatura. Pacotes e áudio avulso não estão habilitados no checkout.
