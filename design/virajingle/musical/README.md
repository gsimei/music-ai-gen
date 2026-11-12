# ViraJingle — versão musical aprovada (A)

Marca com nota dupla no lugar do `n` e J com a virada original.
Os arquivos finais ficam em `public/brand/musical/`:

| Arquivo | Uso | PNG |
| --- | --- | --- |
| `virajingle-logo.svg` / `.png` | Logo verde `#173E32`, para fundos claros | 3200 px de largura |
| `virajingle-logo-white.svg` / `.png` | Logo branca pura `#FFFFFF`, para fundo verde ou escuro | 3200 px de largura |
| `virajingle-j.svg` / `.png` | J verde isolado com a virada original | 1024 px de largura |

Todos têm fundo transparente. Os SVGs contêm curvas vetoriais reais, sem imagem
embutida, texto ou dependência de fontes. A logo branca usa os mesmos caminhos da
verde. Há uma pequena margem transparente nos arquivos; preserve suas proporções.

`preview.png` mostra as três opções sobre fundos de contraste; os fundos pertencem
somente à prévia. `virajingle-musical-kit.zip` reúne os arquivos de marca, o ícone do aplicativo e este guia.

## Origem e reprodução

`source-approved.png` preserva a prévia A aprovada na conversa, criada com a
ferramenta de imagem integrada. O pedido visual foi manter a tipografia moderna e
o J com a virada, adaptando apenas o `n` a uma dupla de notas musicais com peso
compatível com as letras, em verde floresta e creme.

Os arquivos finais são vetorizados a partir dos contornos dessa prévia e exportados
com cores uniformes. A folha de notas enviada pelo usuário serviu como referência
visual da prévia; não é distribuída neste kit.

Para reproduzir, use Python 3.12 com `Pillow==13.0.0`, `vtracer==0.6.15` e ImageMagick:

```sh
python design/virajingle/musical/generate_assets.py
```

A variante está aplicada nos cabeçalhos, no bloco verde da landing e nos e-mails.
O gerador também cria `virajingle-icon.svg` e `.png`: J branco sobre fundo verde
quadrado de 512 × 512, com margem segura para recorte. Esses ícones têm fundo
opaco e são usados no favicon e no manifesto; cópias ficam em `public/icon.*`.
As três opções de logo acima continuam transparentes. As logos anteriores
permanecem disponíveis como histórico.
