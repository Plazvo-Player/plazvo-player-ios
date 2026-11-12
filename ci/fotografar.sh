#!/bin/bash
# Abre o app no simulador (iPhone e iPad) e guarda uma foto de cada tela.
set -euo pipefail
APP="build/Build/Products/Debug-iphonesimulator/PlazvoPlayer.app"
ID_DO_APP="com.plazvo.player"
mkdir -p resultado/telas

# Escolhe o simulador mais novo do tipo pedido (iPhone ou iPad): "udid|nome|sistema".
escolher() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, re, sys
tipo = sys.argv[1]
melhor = None
for sistema, aparelhos in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", sistema)
    if not m:
        continue
    versao = (int(m.group(1)), int(m.group(2)))
    for a in aparelhos:
        nome = a["name"]
        if not a.get("isAvailable", True) or not nome.startswith(tipo):
            continue
        comum = re.fullmatch(r"iPhone (\d+)", nome)
        if comum:
            gosto = (2, int(comum.group(1)))
        elif "iPad Pro 11" in nome:
            gosto = (2, 0)
        elif re.fullmatch(r"iPad \(.*\)", nome):
            gosto = (1, 0)
        else:
            gosto = (0, 0)
        nota = (versao, gosto)
        if melhor is None or nota > melhor[0]:
            melhor = (nota, a["udid"], nome, "iOS %d.%d" % versao)
if melhor is None:
    sys.exit(1)
print("|".join(melhor[1:]))
' "$1"
}

fotografar() { # $1 = iPhone ou iPad; $2 = nome do arquivo da foto
  local linha udid nome sistema
  if ! linha="$(escolher "$1")"; then
    echo "Simulador de $1: não há nesta máquina" | tee -a resultado/resumo.txt
    return 1
  fi
  udid="$(echo "$linha" | cut -d'|' -f1)"
  nome="$(echo "$linha" | cut -d'|' -f2)"
  sistema="$(echo "$linha" | cut -d'|' -f3)"
  echo "Simulador: $nome ($sistema)" | tee -a resultado/resumo.txt

  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl ui "$udid" appearance dark || true
  xcrun simctl status_bar "$udid" override --time "14:30" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
  xcrun simctl install "$udid" "$APP"
  xcrun simctl launch "$udid" "$ID_DO_APP" -AppleLanguages "(pt-BR)" -AppleLocale "pt_BR" > /dev/null
  sleep 8
  xcrun simctl io "$udid" screenshot "resultado/telas/$2" > /dev/null 2>&1
  xcrun simctl terminate "$udid" "$ID_DO_APP" || true
  xcrun simctl shutdown "$udid" || true
}

fotografar "iPhone" "iphone-em-pe.png"
fotografar "iPad" "ipad-em-pe.png"
echo "Fotos: $(ls resultado/telas | tr '\n' ' ')" | tee -a resultado/resumo.txt
