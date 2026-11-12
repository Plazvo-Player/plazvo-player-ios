#!/bin/bash
# Guarda o resultado (resumo e fotos) no ramo "resultados" do repositório, no lugar do anterior.
set -euo pipefail
if [ ! -d resultado ]; then
  echo "Sem pasta de resultado: nada a guardar"
  exit 0
fi
PASTA="$(mktemp -d)"
cp -R resultado/. "$PASTA/"
cd "$PASTA"
cat > LEIAME.md <<TEXTO
# Resultado da última compilação

Gerado sozinho a cada compilação; substitui o anterior.

- \`resumo.txt\`: o que foi compilado, em qual máquina, e se deu certo.
- \`telas/\`: fotos do app aberto no simulador.
TEXTO
git init -q -b resultados .
git add -A
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "Resultado da compilação ${GITHUB_SHA:0:7}"
AUTH="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $AUTH" \
  push -q -f "https://github.com/${GITHUB_REPOSITORY}.git" resultados
echo "Resultado guardado no ramo resultados"
