#!/bin/bash
# Abre o app no simulador (iPhone e iPad) em cada cena e guarda uma foto de cada uma.
#
# As cenas são as de Core/Sources/PlazvoCore/DemoScene.swift: a compilação do simulador abre a
# cena pedida com "-PlazvoCena <nome>" e deita a tela com "-PlazvoDeitado sim". Quando a cena
# está pronta, o app escreve Documents/cena.txt (a cena, a posição da tela, o tamanho da janela e
# o que estava aberto); a foto só é tirada depois disso, e só vale quando a tela parou de mudar.
#
# Além das fotos, fica em resultado/telas/fotos.txt uma linha por foto (quanto demorou e o que o
# app disse), para achar o motivo quando uma foto sai errada.
set -euo pipefail
APP="build/Build/Products/Debug-iphonesimulator/PlazvoPlayer.app"
ID_DO_APP="com.plazvo.player"
mkdir -p resultado/telas
DETALHES="resultado/telas/fotos.txt"
: > "$DETALHES"
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

# Deixa o simulador em português do Brasil: o teclado, a data e a hora da barra do alto saem como
# num aparelho daqui. Tem de ser antes de ligar o simulador.
idioma() { # $1 = udid
  local pasta="$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Library/Preferences"
  local arquivo="$pasta/.GlobalPreferences.plist"
  mkdir -p "$pasta"
  if [ ! -f "$arquivo" ]; then plutil -create binary1 "$arquivo"; fi
  plutil -replace AppleLanguages -json '["pt-BR"]' "$arquivo"
  plutil -replace AppleLocale -string "pt_BR" "$arquivo"
  plutil -replace AppleKeyboards -json '["pt_BR@sw=QWERTY;hw=Automatic"]' "$arquivo"
}

# Liga o simulador e espera ele terminar de ligar. Se passar do limite (12 minutos), o simulador é
# desligado e ligado outra vez; se nem assim ligar, devolve 1 e as fotos desse aparelho ficam de fora.
LIMITE_PARA_LIGAR="${LIMITE_PARA_LIGAR:-720}"
ligar() { # $1 = udid
  local tentativa
  for tentativa in 1 2; do
    xcrun simctl boot "$1" > /dev/null 2>&1 || true
    if perl -e 'alarm shift; exec @ARGV' "$LIMITE_PARA_LIGAR" xcrun simctl bootstatus "$1" -b > /dev/null 2>&1; then
      return 0
    fi
    echo "Simulador: não terminou de ligar em $(( LIMITE_PARA_LIGAR / 60 )) minutos (tentativa $tentativa de 2)" | tee -a resultado/resumo.txt
    xcrun simctl shutdown "$1" > /dev/null 2>&1 || true
  done
  return 1
}

# Deixa o simulador, já ligado, pronto para as fotos, com o app instalado.
preparar() { # $1 = udid
  xcrun simctl ui "$1" appearance dark || true
  xcrun simctl status_bar "$1" override --time "14:30" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
  # Num simulador novo, o teclado abre com uma explicação por cima das teclas ("deslize o dedo
  # para escrever"): fica marcada como já vista, e esse jeito de escrever, desligado.
  xcrun simctl spawn "$1" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true || true
  xcrun simctl spawn "$1" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
  xcrun simctl spawn "$1" defaults write com.apple.keyboard.ContinuousPath KeyboardContinuousPathEnabled -bool false || true
  xcrun simctl install "$1" "$APP"
}

# Abre o app numa cena, espera ela ficar pronta e tira a foto.
foto() { # $1 = udid; $2 = nome da foto (sem .png); $3 = cena; $4 = "deitado" (opcional)
  local udid="$1" nome="$2" cena="$3" deitado="${4:-}"
  local dados pronto espera=0 largura altura posicao inicio pronta tiradas=1
  local imagem="resultado/telas/$nome.png" anterior="resultado/telas/.anterior.png"
  inicio="$(date +%s)"
  xcrun simctl terminate "$udid" "$ID_DO_APP" > /dev/null 2>&1 || true
  dados="$(xcrun simctl get_app_container "$udid" "$ID_DO_APP" data)"
  pronto="$dados/Documents/cena.txt"
  rm -f "$pronto"
  if [ -n "$deitado" ]; then
    xcrun simctl launch "$udid" "$ID_DO_APP" -AppleLanguages "(pt-BR)" -AppleLocale "pt_BR" -PlazvoCena "$cena" -PlazvoDeitado sim > /dev/null
  else
    xcrun simctl launch "$udid" "$ID_DO_APP" -AppleLanguages "(pt-BR)" -AppleLocale "pt_BR" -PlazvoCena "$cena" > /dev/null
  fi
  # Até 3 minutos (a primeira abertura num simulador recém-ligado demora, e as cenas do
  # reprodutor esperam o vídeo abrir).
  until [ -f "$pronto" ] || [ "$espera" -ge 360 ]; do
    sleep 0.5
    espera=$((espera + 1))
  done
  if [ ! -f "$pronto" ]; then
    echo "Foto $nome: a cena \"$cena\" não ficou pronta em 3 minutos" | tee -a resultado/resumo.txt
    FALHAS=$((FALHAS + 1))
  fi
  pronta=$(( $(date +%s) - inicio ))

  # A máquina da nuvem desenha devagar: a foto só vale com a tela parada, isto é, quando duas
  # fotos seguidas saem iguais. (Com o cursor piscando no campo do código pode levar mais vezes.)
  sleep 1
  xcrun simctl io "$udid" screenshot "$imagem" > /dev/null 2>&1 || true
  while [ "$tiradas" -lt 8 ]; do
    cp "$imagem" "$anterior" 2> /dev/null || true
    sleep 2
    xcrun simctl io "$udid" screenshot "$imagem" > /dev/null 2>&1 || true
    tiradas=$((tiradas + 1))
    if cmp -s "$anterior" "$imagem"; then break; fi
  done
  rm -f "$anterior"
  cp "$pronto" "resultado/telas/$nome.txt" 2> /dev/null || true
  posicao="$(grep '^posicao=' "resultado/telas/$nome.txt" 2> /dev/null | cut -d= -f2 || true)"
  echo "$nome: cena $cena; pronta em ${pronta}s; fotos até parar: $tiradas; ao todo $(( $(date +%s) - inicio ))s; $(cat "resultado/telas/$nome.txt" 2> /dev/null | tr '\n' ' ' || true)" >> "$DETALHES"

  if [ -n "$deitado" ]; then
    case "$posicao" in
      deitado-direita | deitado-esquerda)
        # A foto do simulador pode sair com o aparelho em pé: aí a imagem é girada para o lado
        # certo (o app diz no cena.txt para que lado deitou).
        largura="$(sips -g pixelWidth "$imagem" | awk '/pixelWidth/ {print $2}')"
        altura="$(sips -g pixelHeight "$imagem" | awk '/pixelHeight/ {print $2}')"
        if [ "$altura" -gt "$largura" ]; then
          if [ "$posicao" = "deitado-direita" ]; then
            sips -r 270 "$imagem" > /dev/null
          else
            sips -r 90 "$imagem" > /dev/null
          fi
        fi
        ;;
      *)
        # Não deitou: a foto seria igual à da tela em pé, e fica de fora.
        echo "Foto $nome: o simulador não deitou a tela (posição: ${posicao:-não informada}); ficou de fora" | tee -a resultado/resumo.txt
        rm -f "$imagem" "resultado/telas/$nome.txt"
        ;;
    esac
  fi
  xcrun simctl terminate "$udid" "$ID_DO_APP" > /dev/null 2>&1 || true
}

# No iPad o app não consegue deitar a tela sozinho (o iPad só deita quando o aparelho é girado),
# e não existe comando para girar o simulador: só o menu do aplicativo Simulador (Device ›
# Rotate Left). É uma tentativa: se não der, as fotos deitadas do iPad ficam de fora.
deitar_ipad() { # $1 = udid
  local xcode="${DEVELOPER_DIR:-$(xcode-select -p)}"
  open "$xcode/Applications/Simulator.app" --args -CurrentDeviceUDID "$1" || return 1
  sleep 25
  perl -e 'alarm 90; exec @ARGV' osascript \
    -e 'tell application "Simulator" to activate' \
    -e 'delay 3' \
    -e 'tell application "System Events" to tell process "Simulator" to click menu item "Rotate Left" of menu "Device" of menu bar 1' \
    > /dev/null 2>> "$DETALHES"
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

for UDID in $IPHONE $IPAD; do
  idioma "$UDID" || echo "Idioma do simulador: não deu para pôr em português (as fotos saem assim mesmo)" | tee -a resultado/resumo.txt
done

# Ligar o simulador é a parte demorada. Um de cada vez: os dois ligando juntos disputam a máquina
# (um deles chega a falhar e tem de ser ligado de novo), e o que está sendo fotografado fica lento.
if [ -n "$IPHONE" ] && ! ligar "$IPHONE"; then
  echo "Fotos do iPhone: ficaram de fora (o simulador não ligou)" | tee -a resultado/resumo.txt
  FALHAS=$((FALHAS + 1))
  IPHONE=""
fi

if [ -n "$IPHONE" ]; then
  preparar "$IPHONE"
  echo "iPhone pronto $(( SECONDS / 60 )) min depois do começo" >> "$DETALHES"
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
  foto "$IPHONE" "iphone-14-midia" "midia"
  foto "$IPHONE" "iphone-15-midia-recentes" "midia-recentes"
  foto "$IPHONE" "iphone-16-link" "link"
  foto "$IPHONE" "iphone-17-link-errado" "link-errado"
  foto "$IPHONE" "iphone-18-parceiro" "parceiro"
  foto "$IPHONE" "iphone-19-parceiro-ativado" "parceiro-ativado"
  foto "$IPHONE" "iphone-deitado-1-inicial" "inicial" deitado
  foto "$IPHONE" "iphone-deitado-2-conta" "conta" deitado
  foto "$IPHONE" "iphone-deitado-3-codigo" "codigo" deitado
  foto "$IPHONE" "iphone-deitado-4-midia-recentes" "midia-recentes" deitado
  # No iPhone o reprodutor deita a tela sozinho (o vídeo das cenas é deitado).
  foto "$IPHONE" "iphone-deitado-5-reprodutor" "reprodutor" deitado
  foto "$IPHONE" "iphone-deitado-6-video-falhou" "video-falhou" deitado
  xcrun simctl shutdown "$IPHONE" || true
fi

if [ -n "$IPAD" ] && ! ligar "$IPAD"; then
  echo "Fotos do iPad: ficaram de fora (o simulador não ligou)" | tee -a resultado/resumo.txt
  FALHAS=$((FALHAS + 1))
  IPAD=""
fi

if [ -n "$IPAD" ]; then
  preparar "$IPAD"
  echo "iPad pronto $(( SECONDS / 60 )) min depois do começo" >> "$DETALHES"
  foto "$IPAD" "ipad-1-inicial" "inicial"
  foto "$IPAD" "ipad-2-conta" "conta"
  foto "$IPAD" "ipad-3-ativo" "ativo"
  foto "$IPAD" "ipad-4-codigo" "codigo"
  foto "$IPAD" "ipad-5-midia-recentes" "midia-recentes"
  foto "$IPAD" "ipad-6-reprodutor" "reprodutor"
  foto "$IPAD" "ipad-7-parceiro" "parceiro"
  if deitar_ipad "$IPAD"; then
    sleep 5
    foto "$IPAD" "ipad-deitado-1-ativo" "ativo" deitado
    foto "$IPAD" "ipad-deitado-2-conta" "conta" deitado
    foto "$IPAD" "ipad-deitado-3-midia-recentes" "midia-recentes" deitado
    foto "$IPAD" "ipad-deitado-4-reprodutor" "reprodutor" deitado
  else
    echo "iPad deitado: não deu para girar o simulador; as fotos deitadas do iPad ficaram de fora" | tee -a resultado/resumo.txt
  fi
  xcrun simctl shutdown "$IPAD" || true
fi

# Se o app caiu em alguma cena, o começo do relatório da queda vai junto, para achar o motivo.
RELATORIOS="$HOME/Library/Logs/DiagnosticReports"
QUEDAS="$(ls "$RELATORIOS" 2> /dev/null | grep -c '^PlazvoPlayer' || true)"
if [ "${QUEDAS:-0}" -gt 0 ]; then
  echo "Quedas do app no simulador: $QUEDAS" | tee -a resultado/resumo.txt
  head -c 30000 "$(ls -t "$RELATORIOS"/PlazvoPlayer* | head -n 1)" > resultado/queda-do-app.txt || true
fi

echo "Fotos: $(ls resultado/telas | grep -c '\.png$') — $(ls resultado/telas | grep '\.png$' | tr '\n' ' ')" | tee -a resultado/resumo.txt
if [ "$FALHAS" -gt 0 ]; then
  echo "Fotos: $FALHAS cena(s) não ficaram prontas" | tee -a resultado/resumo.txt
  exit 1
fi
