# Implementação no aplicativo

Implementado em `codex/implement-jinglepro-design`, a partir da master `6a18c8e`.

- Landing com demonstrações reais, navegação por âncoras, FAQ animado e pausa de movimento.
- Login, cadastro, recuperação de senha, conta e páginas de erro com a mesma identidade.
- Criação em três passos, escolhas nativas de ritmo/voz/clima e upload com ordenação de cinco fotos.
- Estúdio organizado em letra, músicas e vídeo; rodada recente em destaque, histórico acessível, favorita preservada e conversa opcional.
- Biblioteca com estados e ações de continuidade; entrega com vídeo, MP3 e legenda.
- Rotas antigas preservadas com componentes e estilos compatíveis.

## Adaptações do protótipo

A conta continua sendo criada antes da campanha, preservando o fluxo de autenticação e a associação segura das fotos existente. O cadastro no terceiro passo, sugerido na prancha, exigiria uma mudança funcional separada.

O player usa controles nativos e a duração real do arquivo. A prévia do formulário é estática e identificada como tal; o vídeo final mantém fotos em movimento e transições. Preço, número de rodadas e ajustes disponíveis continuam ligados às regras do produto.

## Correções

A biblioteca usa `OrderAsset#playback_url`, priorizando o MP3 arquivado. Pedidos com pagamento falho podem retomar o checkout: reutilizamos a sessão aberta, reconciliamos pagamento já efetuado e só substituímos uma sessão expirada. Notificações de falha atrasadas não desfazem pagamentos confirmados.

Nas campanhas, a audição usa uma cópia com marca sonora e acesso autenticado. O download limpo é liberado somente para a versão da rodada aprovada. Os originais e trechos limpos ficam bloqueados nas rotas públicas do Active Storage, inclusive por links antigos; o vídeo final continua usando o áudio limpo. Para preparar as prévias de campanhas existentes após a implantação, executar `bin/rails campaigns:prepare_auditions` com os workers ativos (opcional: `CAMPAIGN_ID`). Isso reutiliza os arquivos e não solicita novas gerações à Mureka. Reiniciar os processos da aplicação para carregar o bloqueio do armazenamento.

Áudio reproduzido ainda pode ser gravado. A mudança não revoga URLs externas da Mureka que já tenham sido expostas.

## Verificação

- Suíte final: 1.005 testes, 2.533 assertions, sem falhas ou erros. Após o último ajuste de texto, 22 testes de integração passaram, com 197 assertions.
- Navegador: desktop e viewport de celular (390 px); cinco fotos na ordem 5,1,2,3,4; seleção de acústico/voz feminina/acolhedor; edição da letra com histórico; favorita de rodada anterior; montagem real de MP4 com 30 segundos; cópia de legenda; login/cadastro/recuperação e visibilidade de senha.
- Campanha local de QA 14, pedido 60: áudio reutilizado de arquivos existentes para conferir interface e renderização sem novas chamadas pagas à Mureka. Nenhum pagamento real realizado nesta implementação. Recuperação Stripe coberta por testes com respostas simuladas.
- Compilação local do Tailwind: falha anterior ao redesign persiste, com SIGKILL do executável nativo. CSS novo servido e verificado no aplicativo. Build de produção não validado nesta tarefa.

A integração na `master` e a implantação em produção são etapas separadas da entrega desta branch para revisão.
