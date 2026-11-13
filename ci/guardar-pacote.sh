#!/bin/bash
# Guarda o pacote do aparelho (ci/pacote.sh) num rascunho de versão ("draft release") do
# repositório, no lugar do anterior. Um rascunho só quem cuida do repositório enxerga e baixa:
# o pacote não entra no repositório (é grande) nem fica à vista do público.
# Um rascunho por tipo de máquina: "pacote-de-teste-<máquina>".
set -euo pipefail
PACOTE="$(ls pacote/*.ipa 2> /dev/null | head -n 1 || true)"
if [ -z "$PACOTE" ]; then
  echo "Sem pacote do aparelho: nada a guardar"
  exit 0
fi
export GH_TOKEN="$GITHUB_TOKEN"
MARCA="pacote-de-teste-${MAQUINA:-mac}"
ANTIGOS="$(gh api "repos/${GITHUB_REPOSITORY}/releases?per_page=100" \
  --jq ".[] | select(.draft and .tag_name == \"$MARCA\") | .id")"
for ANTIGO in $ANTIGOS; do
  gh api -X DELETE "repos/${GITHUB_REPOSITORY}/releases/$ANTIGO" > /dev/null
done
gh release create "$MARCA" "$PACOTE" --repo "$GITHUB_REPOSITORY" --draft --target "$GITHUB_SHA" \
  --title "Pacote de teste (${MAQUINA:-mac})" \
  --notes "Pacote sem assinatura da compilação ${GITHUB_SHA:0:7}. É um rascunho: não é uma versão publicada." > /dev/null
echo "Pacote do aparelho guardado no rascunho $MARCA" | tee -a resultado/resumo.txt
