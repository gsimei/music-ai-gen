---
name: project-criar-caminho-b
description: Plano do redesign "Criar campanha caminho B" (13/11/2026): isolamento de CSS em ui.css/.criar, armadilhas de especificidade e JS compartilhado com o estúdio
metadata:
  type: project
---

Plano em `docs/superpowers/plans/2026-11-13-criar-caminho-b-plan.md` (design aprovado em `docs/superpowers/specs/2026-11-13-criar-caminho-b-design.md`).

- O layout lista os CSS pelo nome (`app/views/layouts/application.html.erb:29`); o CLAUDE.md fala em glob, mas `ui.css` só carrega se entrar nessa lista.
- `studio_app.css` tem regras SEM escopo para `.campaign-builder/.campaign-main/.campaign-progress/.campaign-step` e `studio.css` tem `.studio-home h2` (0,1,1): o Criar novo usa só `ui-` e regras sob `.criar` (>= 0,2,0). Por isso testes com `form.campaign-builder` migram para `form.ui-form`.
- `campaign_form_controller.js` e `genre_preview_controller.js` são compartilhados com o estúdio (`_video_appearance`, `_sound_fields`): alvos novos opcionais (`hasXTarget`); `previewCta()` assume `ctaTarget`/`ctaColorTarget`.
- Decisão "Sem faixa": hidden `campaign[show_cta]` controlado por JS + rádio `call_to_action=""` (servidor já aceita `show_cta=0, call_to_action=""`), não atributo virtual.
- Prévia = um `<dialog>` aberto no desktop / modal no celular (nó único); cartão do player = nó único dentro do passo 2.
- Verificação no navegador: parar no passo 3; nunca "Testar sem cobrança" (dispara GenerateLyricsJob/Mureka com adapter :async).

**Why:** evitar a briga de especificidade que motivou o redesign e não quebrar o estúdio.
**How to apply:** ao planejar telas novas do estúdio (fatia 3), reaproveitar os componentes `ui-` e remover a duplicação de `_cta_fields`/`_sound_fields`.
