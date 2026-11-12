#!/bin/bash
# Anota o que há na máquina que compila (sistema, Xcode, simuladores) no resumo do resultado.
set -euo pipefail
mkdir -p resultado

# Usa o Xcode mais novo instalado na máquina (sem ser versão de teste) nos passos seguintes.
XCODE="$(ls -d /Applications/Xcode_*.app 2>/dev/null | grep -v -i -E 'beta|candidate|_rc' | sort -V | tail -n 1 || true)"
if [ -n "$XCODE" ]; then
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
  if [ -n "${GITHUB_ENV:-}" ]; then echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"; fi
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
ler() { /usr/bin/plutil -extract "$1" raw "$SDK/SDKSettings.plist" 2>/dev/null || echo "?"; }
{
  echo "Compilação: $(date -u '+%d/%m/%Y %H:%M:%S') (UTC)"
  echo "Envio (commit): ${GITHUB_SHA:-local}"
  echo "Máquina: ${MAQUINA:-?} — $(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"
  echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "Swift: $(swift --version 2>&1 | head -n 1)"
  echo "SDK do iOS: $(xcrun --sdk iphoneos --show-sdk-version)"
  echo "iOS mínimo que este Xcode aceita: $(ler SupportedTargets.iphoneos.MinimumDeploymentTarget)"
  echo "iOS mínimo recomendado por este Xcode: $(ler SupportedTargets.iphoneos.RecommendedDeploymentTarget)"
  echo
  echo "Xcodes instalados:"
  ls /Applications | grep -i '^Xcode' | sed 's/^/  /' || true
  echo
  echo "Sistemas de simulador:"
  xcrun simctl list runtimes | sed 's/^/  /'
  echo
} | tee resultado/resumo.txt
