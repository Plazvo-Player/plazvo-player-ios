#!/bin/bash
# Busca o motor de vídeo do app: o MobileVLCKit, do projeto VLC (VideoLAN).
#
# Ele não fica no repositório (é grande e não é nosso): vem do endereço oficial do VLC, na versão
# anotada aqui, e só é usado se o arquivo baixado for exatamente o esperado (SHA-256). O endereço e
# o SHA-256 são os que o próprio VLC publica para essa versão (no pacote "MobileVLCKit" do CocoaPods).
#
# Para trocar de versão: mudar ARQUIVO e SHA256 juntos, depois de conferir os dois na fonte oficial.
set -euo pipefail
ARQUIVO="MobileVLCKit-3.7.5-a213fd11-6de05adc.tar.xz"
SHA256="a76f7a6cfcde4209b56f943e6e18400659d8a7a93ff482f8b1d059468d11e6be"
ENDERECO="https://download.videolan.org/pub/cocoapods/prod/$ARQUIVO"
DESTINO="Vendor"
MARCA="$DESTINO/.motor-de-video"

anotar() { if [ -d resultado ]; then echo "$1" | tee -a resultado/resumo.txt; else echo "$1"; fi; }

if [ -d "$DESTINO/MobileVLCKit.xcframework" ] && [ "$(cat "$MARCA" 2> /dev/null || true)" = "$SHA256" ]; then
  anotar "Motor de vídeo: MobileVLCKit 3.7.5 (já estava na máquina, conferido antes)"
  exit 0
fi

rm -rf "$DESTINO/MobileVLCKit.xcframework" "$MARCA"
mkdir -p "$DESTINO"
curl --fail --location --silent --show-error --retry 3 --retry-delay 5 --max-time 1200 \
  --proto '=https' --proto-redir '=https' --tlsv1.2 -o "$DESTINO/$ARQUIVO" "$ENDERECO"

ACHADO="$(shasum -a 256 "$DESTINO/$ARQUIVO" | awk '{print $1}')"
if [ "$ACHADO" != "$SHA256" ]; then
  rm -f "$DESTINO/$ARQUIVO"
  anotar "Motor de vídeo: FALHOU, o arquivo baixado não é o esperado (SHA-256 $ACHADO)"
  exit 1
fi

# Do pacote, só a pasta do motor (o resto é documentação e exemplos).
tar -xJf "$DESTINO/$ARQUIVO" -C "$DESTINO" --strip-components 1 "MobileVLCKit-binary/MobileVLCKit.xcframework"
rm -f "$DESTINO/$ARQUIVO"
test -f "$DESTINO/MobileVLCKit.xcframework/Info.plist"
echo "$SHA256" > "$MARCA"
anotar "Motor de vídeo: MobileVLCKit 3.7.5 baixado de download.videolan.org e conferido (SHA-256 ${SHA256:0:12}…)"
