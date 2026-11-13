---
name: criar-caminho-b-patterns
description: Padrões do redesign do Criar (ui.css, .criar, dialog único de prévia, chips de contato com hidden show_cta, fotos que se somam)
metadata:
  type: project
---

O Criar usa só `ui.css` (seletores `.criar`/`.ui-`, sem hex, sem `!important`) e a raiz `.studio-home.criar`; nunca classes `campaign-*`/`studio-field*` no passo 1.

- Prévia = um único `dialog.ui-stage` (`show()` no desktop ≥ 960 px via matchMedia, `showModal()` no celular). Nunca setar `display` sem `[open]` no CSS do dialog. `show()` rouba o foco: o controller restaura (`showStageQuietly`).
- "Sem faixa" = rádio `value=""` + `input[type=hidden][name="campaign[show_cta]"]` ("1"/"0" literal) mantido por `chooseCta`; `previewCta()` ramifica por `hasCtaChoiceTarget` porque o mesmo controller roda no estúdio.
- Fotos: o `file_field` fica fora do alvo `photoList` (replaceChildren), escondido por recorte; espaços vazios são `label[for]`; seleção soma, lote inválido é rejeitado inteiro e `input.files` é re-sincronizado.
- **Why:** `.studio-home [hidden]{display:none!important}` e regras sem escopo de studio_app.css vencem quem não usa `.criar` + classe.
- Cuidado: o teste `criar_preview_test.rb` exige `previewThumb` dentro do dialog e dentro do botão "Ver prévia" fora do dialog (contraditório).

Passos 2 e 3 (tarefas 6 e 7):
- Passo 2: a própria `section.ui-step-sound` é o escopo `genre-preview` (tiles, cartão `.ui-player`, `<audio>` sem controls/autoplay). Desktop: `.criar[data-step="2"] .ui-col` ocupa as 2 colunas do form, a section vira grid e o cartão fica na coluna 2 (sticky); `.ui-side` some no passo 2 e a actionbar é limitada à coluna 1. "Sua direção" e o resumo do passo 3 vêm de `sound()` lendo `[data-sound-setting]:checked` (`data-sound-label` = só o nome).
- Onda do player: estado em `data-playing` no botão; animação via `.ui-player:has(.ui-play[data-playing="true"])` só dentro de `prefers-reduced-motion: no-preference`. Foco dentro do cartão floresta precisa de `outline-color: var(--jp-lime)`.
- Erros de campo: `CriarHelper#criar_field_aria`/`criar_field_error` (aria-invalid + aria-describedby com dica + `campaign-<attr>-error`), `.criar .field_with_errors{display:contents}`.
- Preço: `.ui-price` na `.ui-side`, visível só em `data-step="3"`; sem botão (o único submit é o da actionbar).
- **Why:** rolagem suave ao trocar de passo (`scrollIntoView smooth`) corre com testes de sistema que rolam logo em seguida e terminam fora do lugar; ficou `behavior: "auto"`.
- `_sound_fields` e `.campaign-genre-preview` foram apagados (só o Criar os usava); sobram CSS órfão em studio_identity/jinglepro (`.campaign-sound-fields`, `.jp-genres`, `.campaign-style*`).
