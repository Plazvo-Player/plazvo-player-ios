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
# (LC_ALL=C e -a: procura byte a byte, também dentro dos arquivos que não são texto.)
if LC_ALL=C grep -R -a -q -F "api.plazvo.com" "$APP"; then
  echo "Conferência do servidor: FALHOU, o app do simulador tem o endereço api.plazvo.com" | tee -a resultado/resumo.txt
  exit 1
fi
echo "Conferência do servidor: o app do simulador não tem o endereço api.plazvo.com" | tee -a resultado/resumo.txt

# O app do aparelho (o que fala com o servidor de verdade) também tem de compilar. Sai sem
# assinatura: não dá para instalar; serve para provar que o código do aparelho compila.
set +e
xcodebuild \
  -project PlazvoPlayer.xcodeproj -scheme PlazvoPlayer -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build-aparelho \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build > build-aparelho.log 2>&1
CODIGO=$?
set -e

grep -E "(error|warning): " build-aparelho.log | sort -u > resultado/avisos-e-erros-aparelho.txt || true

if [ "$CODIGO" -ne 0 ]; then
  echo "Compilação para o aparelho: FALHOU (código $CODIGO)" | tee -a resultado/resumo.txt
  cat resultado/avisos-e-erros-aparelho.txt
  tail -n 40 build-aparelho.log | tee resultado/fim-do-registro-aparelho.txt
  exit 1
fi
echo "Compilação para o aparelho (sem assinatura): deu certo" | tee -a resultado/resumo.txt

APARELHO="build-aparelho/Build/Products/Debug-iphoneos/PlazvoPlayer.app"
test -d "$APARELHO"

# O contrário da conferência do simulador: o app do aparelho tem de levar o endereço do servidor.
if ! LC_ALL=C grep -R -a -q -F "api.plazvo.com" "$APARELHO"; then
  echo "Conferência do servidor: FALHOU, o app do aparelho não tem o endereço api.plazvo.com" | tee -a resultado/resumo.txt
  exit 1
fi
echo "Conferência do servidor: o app do aparelho tem o endereço api.plazvo.com" | tee -a resultado/resumo.txt

# E o app do aparelho não leva o que é só das fotos e dos testes (as cenas e o servidor de mentira).
if LC_ALL=C grep -R -a -q -F -e "PlazvoCena" -e "PlazvoDeitado" "$APARELHO"; then
  echo "Conferência das cenas: FALHOU, o app do aparelho tem as cenas das fotos" | tee -a resultado/resumo.txt
  exit 1
fi
echo "Conferência das cenas: o app do aparelho não tem as cenas das fotos" | tee -a resultado/resumo.txt
