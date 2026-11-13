#!/bin/bash
# Monta o pacote de instalar no aparelho (.ipa): compila o app do aparelho do jeito que ele vai
# para o aparelho (Release) e o empacota.
#
# O pacote sai SEM assinatura: não abre em aparelho nenhum do jeito que está. Quem instala assina
# com a própria Conta Apple (programa de instalar no computador) ou com a conta de desenvolvedor.
# O pacote não vai para o repositório: ci/guardar.sh o deixa num rascunho de versão, que só quem
# cuida do repositório enxerga.
#
# Roda depois de ci/compilar.sh (que gera o projeto do Xcode e confere o código).
set -euo pipefail
mkdir -p resultado
anotar() { echo "$1" | tee -a resultado/resumo.txt; }

set +e
xcodebuild \
  -project PlazvoPlayer.xcodeproj -scheme PlazvoPlayer -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build-pacote \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build > build-pacote.log 2>&1
CODIGO=$?
set -e

grep -E "(error|warning): " build-pacote.log | sort -u > resultado/avisos-e-erros-pacote.txt || true

if [ "$CODIGO" -ne 0 ]; then
  anotar "Pacote do aparelho: FALHOU, a compilação do pacote não passou (código $CODIGO)"
  cat resultado/avisos-e-erros-pacote.txt
  tail -n 40 build-pacote.log | tee resultado/fim-do-registro-pacote.txt
  exit 1
fi

APARELHO="build-pacote/Build/Products/Release-iphoneos/PlazvoPlayer.app"
if [ ! -d "$APARELHO" ]; then
  anotar "Pacote do aparelho: FALHOU, a compilação não deixou o app onde era esperado"
  exit 1
fi

VERSAO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APARELHO/Info.plist")"
NUMERO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APARELHO/Info.plist")"
NOME="plazvo-player-iphone-v${VERSAO}-sem-assinatura.ipa"

rm -rf pacote
mkdir -p pacote/Payload
cp -R "$APARELHO" pacote/Payload/
APP="pacote/Payload/PlazvoPlayer.app"

# Todo iPhone e iPad que roda o iOS deste app é de 64 bits (arm64). O motor de vídeo vem também
# com o código dos aparelhos antigos de 32 bits, que só ocupa espaço: fica só o de 64 bits.
for PECA in "$APP"/Frameworks/*.framework; do
  [ -d "$PECA" ] || continue
  BINARIO="$PECA/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PECA/Info.plist")"
  TIPOS="$(lipo -archs "$BINARIO")"
  if [ "$TIPOS" != "arm64" ]; then
    lipo "$BINARIO" -thin arm64 -output "$BINARIO.arm64"
    mv "$BINARIO.arm64" "$BINARIO"
  fi
  anotar "Pacote do aparelho: $(basename "$PECA") — de \"$TIPOS\" ficou \"$(lipo -archs "$BINARIO")\""
done

TIPOS_DO_APP="$(lipo -archs "$APP/PlazvoPlayer")"
if [ "$TIPOS_DO_APP" != "arm64" ]; then
  anotar "Pacote do aparelho: FALHOU, o app saiu para \"$TIPOS_DO_APP\" (esperado: arm64)"
  exit 1
fi

# As mesmas conferências do app compilado, agora no que vai dentro do pacote.
if ! LC_ALL=C grep -R -a -q -F "api.plazvo.com" "$APP"; then
  anotar "Pacote do aparelho: FALHOU, falta o endereço api.plazvo.com"
  exit 1
fi
if LC_ALL=C grep -R -a -q -F -e "PlazvoCena" -e "PlazvoDeitado" "$APP"; then
  anotar "Pacote do aparelho: FALHOU, o pacote tem as cenas das fotos"
  exit 1
fi

(cd pacote && zip -q -r -y "$NOME" Payload)
rm -rf pacote/Payload

TAMANHO="$(stat -f %z "pacote/$NOME")"
SHA256="$(shasum -a 256 "pacote/$NOME" | awk '{print $1}')"
{
  echo "arquivo=$NOME"
  echo "versao=$VERSAO"
  echo "numero=$NUMERO"
  echo "bytes=$TAMANHO"
  echo "sha256=$SHA256"
  echo "envio=${GITHUB_SHA:-local}"
} > resultado/pacote.txt
anotar "Pacote do aparelho (sem assinatura): $NOME, $TAMANHO bytes, SHA-256 $SHA256"
