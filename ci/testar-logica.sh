#!/bin/bash
# Roda os testes da lógica do app (pasta Core), sem simulador.
set -euo pipefail
mkdir -p resultado
cd Core
set +e
swift test > ../testes-da-logica.log 2>&1
CODIGO=$?
set -e
cd ..
grep -E "^(✘|✔ Test run|✘ Test run|error:)" testes-da-logica.log > resultado/testes-da-logica.txt || true
tail -n 30 testes-da-logica.log >> resultado/testes-da-logica.txt
if [ "$CODIGO" -ne 0 ]; then
  echo "Testes da lógica: FALHARAM (código $CODIGO)" | tee -a resultado/resumo.txt
  cat resultado/testes-da-logica.txt
  exit 1
fi
echo "Testes da lógica: $(grep -E 'Test run with' testes-da-logica.log | tail -n 1 | sed 's/^[^T]*//')" | tee -a resultado/resumo.txt
