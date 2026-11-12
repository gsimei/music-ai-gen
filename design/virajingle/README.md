# ViraJingle — identidade visual

A marca ativa é a **versão musical A**: letras modernas, uma dupla de notas no `n`
e o J com a virada original. Verde floresta (`#173E32`), branco (`#FFFFFF`) e
creme (`#F6F5ED`) acompanham a paleta do produto.

Os arquivos usados pelo app ficam em `public/brand/musical/`:

- `virajingle-logo.svg` e `.png`: logo verde com fundo transparente.
- `virajingle-logo-white.svg` e `.png`: logo branca para fundos escuros.
- `virajingle-j.svg` e `.png`: J isolado com fundo transparente.
- `virajingle-icon.svg` e `.png`: J branco sobre verde, quadrado de 512 × 512,
  com margem segura para recortes do ícone. Também exportado em `public/icon.*`.

Os SVGs contêm contornos vetoriais e não dependem de fontes instaladas. O cabeçalho
compartilhado serve a landing, o estúdio, a biblioteca e as telas de acesso; o
bloco verde final da landing usa a logo branca. E-mails usam o PNG verde anexado
inline, sem depender de uma imagem remota. Favicon e manifesto usam o J quadrado.

Para reproduzir, use Python 3.12, instale `requirements.txt` em ambiente separado
e execute `python design/virajingle/generate_assets.py`. ImageMagick exporta os
PNGs. Essas ferramentas são apenas de design, não dependências de produção.

Veja `musical/README.md` para a origem e `musical/preview.png` para a prancha.
O pacote atualizado fica em `musical/virajingle-musical-kit.zip`. Os arquivos
antigos diretamente em `public/brand/`, as fontes e as prévias antigas foram
preservados como histórico, mas não são usados pela interface atual.

A prévia real de e-mail está em desenvolvimento em
`/rails/mailers/users_mailer/reset_password_instructions`; usa dados ilustrativos
e não envia mensagens.
