#!/usr/bin/env bash
# Pruebas de humo contra un contenedor YA arrancado.
#   uso: bash tests/smoke.sh http://127.0.0.1:5055
#   SIN_INTERNET=1 se salta la síntesis (edge-tts necesita internet)
set -uo pipefail
BASE="${1:?Uso: smoke.sh BASE_URL}"
FALLOS=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
mal()  { printf '  \033[31m✘\033[0m %s\n' "$1"; FALLOS=$((FALLOS+1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else mal "$1"; fi; }
post() { curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/synthesize" -H 'Content-Type: application/json' -d "$1"; }

echo "▶ Funcionamiento básico"
check "Health responde"                "curl -sf $BASE/health | grep -q '\"status\": \"ok\"'"
check "Sirve la interfaz web"          "curl -sf $BASE/ | grep -q 'voiceSelect'"
check "Lista las 4 voces base"         "[ \$(curl -sf $BASE/api/voices | python3 -c 'import sys,json;print(len(json.load(sys.stdin)[\"voices\"]))') -ge 4 ]"
check "La lista de voces no expone rutas internas" "! curl -sf $BASE/api/voices | grep -q '/app/'"

echo "▶ Seguridad y validación"
check "Rechaza texto vacío"                  "[ \"\$(post '{\"text\":\"\"}')\" = 400 ]"
LARGO=$(python3 -c 'import json;print(json.dumps({"text":"a"*6000}))')
check "Rechaza textos de más de 5000 letras" "[ \"\$(post '$LARGO')\" = 400 ]"
check "Rechaza JSON inválido"                "[ \"\$(post 'esto no es json')\" = 400 ]"
check "No permite salir de la carpeta de audios" \
      "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --path-as-is $BASE/audio/..%2F..%2Fapp%2Fserver.py)\" = 404 ]"

if [ -z "${SIN_INTERNET:-}" ]; then
    echo "▶ Síntesis real"
    R=$(curl -s -m 60 -X POST "$BASE/api/synthesize" -H 'Content-Type: application/json' \
        -d '{"text":"Prueba automática del pipeline.","voice":"colombiano","name":"ci"}')
    check "Genera audio con una voz normal" "echo '$R' | grep -q '\"success\": true'"
    check "El WAV se entrega como descarga" \
          "curl -sD - -o /dev/null '$BASE/audio/ci.wav?download=1' | grep -qi 'content-disposition: attachment'"
    check "El WAV no está vacío" "[ \$(curl -s $BASE/audio/ci.wav | wc -c) -gt 20000 ]"
    RVC=$(curl -sf "$BASE/api/voices" | python3 -c 'import sys,json;v=[x["id"] for x in json.load(sys.stdin)["voices"] if x["id"].startswith("rvc-")];print(v[0] if v else "")')
    if [ -n "$RVC" ]; then
        R=$(curl -s -m 240 -X POST "$BASE/api/synthesize" -H 'Content-Type: application/json' \
            -d "{\"text\":\"Prueba de voz clonada.\",\"voice\":\"$RVC\"}")
        check "Genera audio con voz clonada RVC ($RVC)" "echo '$R' | grep -q '\"success\": true'"
    else
        echo "  (sin modelos RVC instalados: se salta la prueba de voz clonada)"
    fi
fi

echo
if [ "$FALLOS" -eq 0 ]; then echo "✅ Todas las pruebas pasaron"; else echo "❌ $FALLOS prueba(s) fallaron"; exit 1; fi
