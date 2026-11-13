#!/bin/bash
# Confere os tipos do código do app (pasta App) fora de um Mac (no Linux), com imitações do
# SwiftUI, do UIKit, do UniformTypeIdentifiers e do motor do VLC (pasta stubs).
#
# Não substitui a compilação num Mac: as imitações só têm o que o app usa, escrito à mão, e não
# garantem que o SwiftUI de verdade aceite o mesmo. Serve para pegar erro de digitação e de tipo
# antes de gastar uma compilação na nuvem.
#
# Precisa do Swift 6.3 para Linux no PATH (o mesmo dos testes da pasta Core).
# Uso: bash tools/conferir-sem-mac/conferir.sh
#   REFAZER=nao  não refaz os módulos das imitações (quando elas não mudaram)
#   LINHAS=300   mostra mais linhas de erro por passada (padrão: 120)
#
# Atenção: um erro num arquivo pode esconder os erros dos arquivos seguintes. Acertar e rodar de
# novo, até não sobrar nenhum.
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../.." && pwd)"
MOD="${TMPDIR:-/tmp}/plazvo-conferir-sem-mac"
mkdir -p "$MOD"

modulo() { # $1 = nome
  swiftc -parse-as-library -emit-module -module-name "$1" -emit-module-path "$MOD/$1.swiftmodule" \
    -I "$MOD" -swift-version 5 "$AQUI/stubs/$1/$1.swift" 2>&1 | grep -E "error" -A6 || true
}
if [ "${REFAZER:-sim}" = "sim" ] || [ ! -f "$MOD/SwiftUI.swiftmodule" ]; then
  modulo UniformTypeIdentifiers
  modulo UIKit
  modulo MobileVLCKit
  modulo SwiftUI
fi

(cd "$REPO/Core" && swift build 2>&1 | grep -E "error" -A6 || true)
CORE="$REPO/Core/.build/debug/Modules"

conferir() { # $1 = nome da passada; $2 = pasta com os arquivos
  echo "== $1"
  swiftc -typecheck -parse-as-library -swift-version 5 -module-name PlazvoPlayer \
    -I "$MOD" -I "$CORE" "$2"/*.swift "$AQUI"/extras/*.swift 2>&1 \
    | grep -E "error|warning: (var|imm|unused|will never|result of|initialization of|code after|unreachable|main actor|capture|non-sendable|sending|call to main)" -A4 \
    | head -n "${LINHAS:-120}" || true
}

# 1ª passada: o código do aparelho (no Linux, o que fica dentro de "#if targetEnvironment(simulator)" não entra).
conferir "aparelho" "$REPO/App"

# 2ª passada: o código do simulador (os "#if" do simulador passam a valer).
SIM="$(mktemp -d)"
for arquivo in "$REPO"/App/*.swift; do
  sed -e 's/#if targetEnvironment(simulator)/#if true/' -e 's/#if !targetEnvironment(simulator)/#if false/' "$arquivo" > "$SIM/$(basename "$arquivo")"
done
conferir "simulador" "$SIM"
rm -rf "$SIM"
echo "== fim"
