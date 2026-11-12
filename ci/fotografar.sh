#!/bin/bash
# Abre o app no simulador (iPhone e iPad) em cada cena e guarda uma foto de cada uma.
#
# As cenas são as de Core/Sources/PlazvoCore/DemoScene.swift: a compilação do simulador abre a
# cena pedida com "-PlazvoCena <nome>" e deita a tela com "-PlazvoDeitado sim". Quando a cena
# está pronta, o app escreve Documents/cena.txt (a cena, a posição da tela e o tamanho da janela);
# a foto só é tirada depois disso.
set -euo pipefail
APP="build/Build/Products/Debug-iphonesimulator/PlazvoPlayer.app"
ID_DO_APP="com.plazvo.player"
mkdir -p resultado/telas
FALHAS=0

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

# Espera o simulador ligar e deixa-o pronto para as fotos, com o app instalado.
preparar() { # $1 = udid
  xcrun simctl bootstatus "$1" -b > /dev/null
  xcrun simctl ui "$1" appearance dark || true
  xcrun simctl status_bar "$1" override --time "14:30" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
  xcrun simctl install "$1" "$APP"
}

# Abre o app numa cena, espera ela ficar pronta e tira a foto.
foto() { # $1 = udid; $2 = nome da foto (sem .png); $3 = cena; $4 = "deitado" (opcional)
  local udid="$1" nome="$2" cena="$3" deitado="${4:-}"
  local dados pronto espera=0 largura altura posicao
  xcrun simctl terminate "$udid" "$ID_DO_APP" > /dev/null 2>&1 || true
  dados="$(xcrun simctl get_app_container "$udid" "$ID_DO_APP" data)"
  pronto="$dados/Documents/cena.txt"
  rm -f "$pronto"
  if [ -n "$deitado" ]; then
    xcrun simctl launch "$udid" "$ID_DO_APP" -AppleLanguages "(pt-BR)" -AppleLocale "pt_BR" -PlazvoCena "$cena" -PlazvoDeitado sim > /dev/null
  else
    xcrun simctl launch "$udid" "$ID_DO_APP" -AppleLanguages "(pt-BR)" -AppleLocale "pt_BR" -PlazvoCena "$cena" > /dev/null
  fi
  # Até 90 segundos (a primeira abertura num simulador recém-ligado demora).
  until [ -f "$pronto" ] || [ "$espera" -ge 180 ]; do
    sleep 0.5
    espera=$((espera + 1))
  done
  if [ ! -f "$pronto" ]; then
    echo "Foto $nome: a cena \"$cena\" não ficou pronta em 90 segundos" | tee -a resultado/resumo.txt
    FALHAS=$((FALHAS + 1))
  fi
  sleep 1
  xcrun simctl io "$udid" screenshot "resultado/telas/$nome.png" > /dev/null 2>&1
  cp "$pronto" "resultado/telas/$nome.txt" 2> /dev/null || true

  # A foto do simulador sai sempre com o aparelho em pé: com a tela deitada, a imagem é girada
  # para o lado certo (o app diz no cena.txt para que lado deitou).
  if [ -n "$deitado" ]; then
    largura="$(sips -g pixelWidth "resultado/telas/$nome.png" | awk '/pixelWidth/ {print $2}')"
    altura="$(sips -g pixelHeight "resultado/telas/$nome.png" | awk '/pixelHeight/ {print $2}')"
    posicao="$(grep '^posicao=' "resultado/telas/$nome.txt" 2> /dev/null | cut -d= -f2 || true)"
    if [ "$altura" -gt "$largura" ]; then
      case "$posicao" in
        deitado-direita) sips -r 270 "resultado/telas/$nome.png" > /dev/null ;;
        deitado-esquerda) sips -r 90 "resultado/telas/$nome.png" > /dev/null ;;
        *) echo "Foto $nome: o simulador não deitou a tela (posição: ${posicao:-não informada})" | tee -a resultado/resumo.txt ;;
      esac
    fi
  fi
  xcrun simctl terminate "$udid" "$ID_DO_APP" > /dev/null 2>&1 || true
}

IPHONE=""
IPAD=""
if LINHA="$(escolher iPhone)"; then
  IPHONE="$(echo "$LINHA" | cut -d'|' -f1)"
  echo "Simulador: $(echo "$LINHA" | cut -d'|' -f2) ($(echo "$LINHA" | cut -d'|' -f3))" | tee -a resultado/resumo.txt
else
  echo "Simulador de iPhone: não há nesta máquina" | tee -a resultado/resumo.txt
fi
if LINHA="$(escolher iPad)"; then
  IPAD="$(echo "$LINHA" | cut -d'|' -f1)"
  echo "Simulador: $(echo "$LINHA" | cut -d'|' -f2) ($(echo "$LINHA" | cut -d'|' -f3))" | tee -a resultado/resumo.txt
else
  echo "Simulador de iPad: não há nesta máquina" | tee -a resultado/resumo.txt
fi
if [ -z "$IPHONE" ] && [ -z "$IPAD" ]; then
  exit 1
fi

# Ligar o simulador é a parte demorada: os dois começam a ligar juntos.
if [ -n "$IPHONE" ]; then xcrun simctl boot "$IPHONE" || true; fi
if [ -n "$IPAD" ]; then xcrun simctl boot "$IPAD" || true; fi

if [ -n "$IPHONE" ]; then
  preparar "$IPHONE"
  foto "$IPHONE" "iphone-01-inicial" "inicial"
  foto "$IPHONE" "iphone-02-conta" "conta"
  foto "$IPHONE" "iphone-03-codigo" "codigo"
  foto "$IPHONE" "iphone-04-codigo-errado" "codigo-errado"
  foto "$IPHONE" "iphone-05-ativado" "ativado"
  foto "$IPHONE" "iphone-06-nova-chave" "nova-chave"
  foto "$IPHONE" "iphone-07-desconectar" "desconectar"
  foto "$IPHONE" "iphone-08-copiado" "copiado"
  foto "$IPHONE" "iphone-09-ativo" "ativo"
  foto "$IPHONE" "iphone-10-sem-conexao" "sem-conexao"
  foto "$IPHONE" "iphone-11-bloqueado" "bloqueado"
  foto "$IPHONE" "iphone-12-vencendo" "vencendo"
  foto "$IPHONE" "iphone-13-vencido" "vencido"
  foto "$IPHONE" "iphone-deitado-1-inicial" "inicial" deitado
  foto "$IPHONE" "iphone-deitado-2-conta" "conta" deitado
  foto "$IPHONE" "iphone-deitado-3-codigo" "codigo" deitado
  xcrun simctl shutdown "$IPHONE" || true
fi

if [ -n "$IPAD" ]; then
  preparar "$IPAD"
  foto "$IPAD" "ipad-1-inicial" "inicial"
  foto "$IPAD" "ipad-2-conta" "conta"
  foto "$IPAD" "ipad-3-ativo" "ativo"
  foto "$IPAD" "ipad-deitado-1-ativo" "ativo" deitado
  foto "$IPAD" "ipad-deitado-2-conta" "conta" deitado
  xcrun simctl shutdown "$IPAD" || true
fi

echo "Fotos: $(ls resultado/telas | grep -c '\.png$') — $(ls resultado/telas | grep '\.png$' | tr '\n' ' ')" | tee -a resultado/resumo.txt
if [ "$FALHAS" -gt 0 ]; then
  echo "Fotos: $FALHAS cena(s) não ficaram prontas" | tee -a resultado/resumo.txt
  exit 1
fi
