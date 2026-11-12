#!/bin/bash
# Gera o projeto do Xcode e compila o app para o simulador.
set -euo pipefail
mkdir -p resultado

if ! command -v xcodegen >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen
fi
echo "XcodeGen: $(xcodegen --version 2>&1 | tail -n 1)" | tee -a resultado/resumo.txt
xcodegen generate

set +e
xcodebuild \
  -project PlazvoPlayer.xcodeproj -scheme PlazvoPlayer -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > build-completo.log 2>&1
CODIGO=$?
set -e

grep -E "(error|warning): " build-completo.log | sort -u > resultado/avisos-e-erros.txt || true
tail -n 40 build-completo.log > resultado/fim-do-registro.txt

if [ "$CODIGO" -ne 0 ]; then
  echo "Compilação: FALHOU (código $CODIGO)" | tee -a resultado/resumo.txt
  cat resultado/avisos-e-erros.txt
  tail -n 40 build-completo.log
  exit 1
fi
echo "Compilação: deu certo" | tee -a resultado/resumo.txt

APP="build/Build/Products/Debug-iphonesimulator/PlazvoPlayer.app"
test -d "$APP"

# Regra do projeto: o app do simulador nunca leva o endereço do servidor de verdade.
if grep -R -a -q "api.plazvo.com" "$APP"; then
  echo "Conferência do servidor: FALHOU, o app do simulador tem o endereço api.plazvo.com" | tee -a resultado/resumo.txt
  exit 1
fi
echo "Conferência do servidor: o app do simulador não tem o endereço api.plazvo.com" | tee -a resultado/resumo.txt
