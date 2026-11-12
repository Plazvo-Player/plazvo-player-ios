#!/bin/bash
# Guarda o resultado (resumo e fotos) num ramo do repositório, no lugar do anterior.
# Um ramo por tipo de máquina: "resultados-<máquina>".
set -euo pipefail
RAMO="resultados-${MAQUINA:-mac}"
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
git init -q -b "$RAMO" .
git add -A
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "Resultado da compilação ${GITHUB_SHA:0:7} (${MAQUINA:-mac})"
AUTH="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $AUTH" \
  push -q -f "https://github.com/${GITHUB_REPOSITORY}.git" "$RAMO"
echo "Resultado guardado no ramo $RAMO"
