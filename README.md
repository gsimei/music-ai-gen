# JinglePro

Plataforma de criação de jingles para negócios, com Rails 8.1, Ruby 4.0.5,
PostgreSQL, Hotwire e Tailwind CSS 4.

## Desenvolvimento local

Com Ruby e PostgreSQL disponíveis:

```sh
bundle install
# Em um checkout novo, copie .env.example para .env e configure as integrações.
# Preserve o .env existente ao retomar o projeto.
bin/rails db:prepare
bin/rails server -b 127.0.0.1 -p 3000
```

Abra [JinglePro local](http://127.0.0.1:3000). Para alterações nas classes
Tailwind, rode `bin/rails tailwindcss:watch` em outro terminal. O `bin/dev`
também inicia o Stripe CLI conforme `Procfile.dev`.

O tema de estúdio usa `app/assets/stylesheets/studio.css` na home e
`app/assets/stylesheets/studio_app.css` no login, cadastro, recuperação de senha,
chat e biblioteca. Esses estilos são servidos pelo Propshaft sem compilação
Tailwind. Os componentes compartilhados ficam em `app/views/shared/`.

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

## Estado ao retomar

- Preços e limites efetivos estão em `config/brands.yml`; a SPEC contém valores diferentes.
- O fluxo atual cria pedidos no estado `paid`; o checkout Stripe está desativado no controller, sem restrição ao ambiente de desenvolvimento. Não está pronto para cobrança real.
- Em 08/11/2026, o fluxo vocal foi validado com APIs reais: chat → letra Mureka → aprovação → duas músicas → reprodução → escolha da variante B → biblioteca e download. Projeto local: `ORD-2026-JKCJF` (`/orders/46/chat`). As variantes tiveram 41,79 s e 35,75 s para um briefing de 30 s; a duração pedida ainda é uma orientação ao provedor.
- A suíte Ruby passou com 907 testes e 1.700 assertions após as correções. Pagamentos, soundtrack e regeneração musical não foram exercitados com APIs reais nesta rodada.
- Home, autenticação, chat e biblioteca compartilham o visual de estúdio. No celular, o chat alterna entre conversa e painel de texto/música.

### Campanhas para o Brasil

A entrada principal agora oferece uma campanha por R$ 79 (valor em `config/brands.yml`), em BRL: briefing guiado → resumo → Stripe Checkout → letra → escolha musical → MP4 vertical e legenda. Pedidos antigos conservam sua moeda. `GET /orders/new` não cria nem paga pedidos.

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

Cada versão ganha um trecho de até 30 segundos, preparado por `PrepareCampaignAudioJob` após arquivar o MP3 original. O player principal reproduz esse trecho com fade de saída; a aprovação só libera quando ele estiver pronto. O vídeo copia o áudio AAC aprovado sem recortar ou aplicar um segundo fade. A música completa continua disponível num player secundário. Campanhas antigas já aprovadas preservam a montagem anterior; versões antigas ainda não aprovadas têm um botão para preparar o trecho. Uma falha no preparo permite tentar novamente sem chamar a Mureka nem consumir rodada.

A [documentação oficial de geração](https://platform.mureka.ai/docs/api/operations/post-v1-song-generate.html), incluindo o schema publicado em seu bundle, anuncia `duration` apenas para V9.5 e no intervalo de 120–300 segundos. Não enviamos `duration: 30`, que não é suportado, nem prometemos que a música original terá 30 segundos. O controle do anúncio é local; o cliente deve conferir se a oferta está completa no trecho antes de aprovar. `audio_preview_seconds` no relatório mede o processamento dessas prévias, separado da renderização do vídeo; o custo monetário da infraestrutura depende do ambiente.

### Chat, recuperação e escolha do trecho

Pedidos de ritmo, voz, clima e instrumentos no chat passam pela mesma validação dos controles visíveis e atualizam a campanha e o briefing. A resposta da IA fornece somente as mudanças solicitadas; confirmações preservam as escolhas atuais. Uma resposta atrasada não sobrescreve controles ou letra alterados enquanto o chat respondia, nem dispara outra geração. O histórico de músicas conserva os snapshots originais.

`GenerateCampaignMusicJob` registra a submissão antes de chamar a Mureka. Uma tarefa com ID salvo é retomada somente por consulta, sem novo POST. Erros transitórios de consulta aguardam até 30 minutos; depois, “Verificar tentativa” consulta o mesmo ID e pode recuperar o resultado. Timeout de submissão ou resposta ambígua não autoriza reenvio automático. HTTP 429 por concorrência tem até três envios com espera; falta de créditos e requisições rejeitadas exigem revisão. Há um teto técnico de cinco pares potencialmente cobrados e doze envios por campanha, separado das três rodadas completas oferecidas ao cliente. Ao atingir o teto, as músicas anteriores continuam disponíveis, mas novas gerações exigem revisão operacional. Estimativas incertas continuam na conta; rejeições explícitas sem tarefa aceita são registradas com estimativa zero.

`RecoverCampaignMusicJob` recupera tarefas interrompidas e está agendado a cada minuto em `config/recurring.yml`. Produção precisa executar o scheduler e os workers do Solid Queue. Em desenvolvimento, a consulta de status da página também solicita recuperação de tarefas paradas. Execute a migração `20261109160000` antes de iniciar os workers atualizados.

Cada música preparada permite ajustar o início do vídeo por um controle deslizante ou pelo segundo inicial, e voltar à sugestão automática. “Preparar e ouvir este trecho” produz uma prévia local de até 30 segundos, com fade; não chama a Mureka nem consome rodada. O original permanece intacto. A aprovação inclui a revisão do corte, impedindo que uma aba antiga aprove um áudio que mudou. O MP4 copia os mesmos pacotes AAC da prévia aprovada, sem novo corte ou codificação. Cortes só podem mudar antes da aprovação.

### Medição de custo por campanha

`GenerationCost` registra cada chamada de letra, cada tentativa musical e cada chamada do chat (incluindo retries), além do tempo de parede e tamanho do vídeo. Valores são **estimativas de API**, não conciliação de fatura nem lucro líquido. A taxa `COST_USD_BRL` (padrão 6) e a versão de preços são gravadas por evento; mudar a configuração não recalcula o passado.

```sh
bin/rails campaigns:costs > tmp/campaign-costs.csv
CAMPAIGN_ID=123 bin/rails campaigns:costs > tmp/campaign-123-costs.csv
```

O CSV separa custo estimado total, parcela incerta, chamadas sem preço, segundos de renderização e tentativas musicais antigas sem registro. `uncertain_api_brl` já está incluído no total — não somar novamente. Falha/timeout não comprova devolução pela Mureka: mantemos a estimativa incerta para conciliação. Renderização local mede tempo, mas não inventa um preço por segundo: servidor, armazenamento acumulado, pagamentos, tributos, atendimento e CAC devem ser acrescentados à análise financeira. Campanhas anteriores à instrumentação têm cobertura parcial; zero eventos não significa custo histórico zero.

Preços usados em 09/11/2026: [Mureka API](https://platform.mureka.ai/pricing) (letra US$ 0,009; música V9 US$ 0,045/unidade, V9.5 US$ 0,15/unidade) e [GPT-4o mini](https://developers.openai.com/api/docs/models/gpt-4o-mini) (US$ 0,15/0,075/0,60 por milhão de tokens de entrada/cache/saída). O modelo de chat existente foi preservado. Rever a tabela quando o provedor alterar preços.

O preço publicado permanece R$ 79. Pacote de quatro campanhas por R$ 199 e áudio avulso por R$ 29,90 são recomendações comerciais, **não produtos habilitados no checkout**.
