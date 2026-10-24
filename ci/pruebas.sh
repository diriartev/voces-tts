#!/usr/bin/env bash
# ==============================================================================
#  Pruebas propias de Voces TTS (las ejecuta ci/revisar.sh, etapa "pruebas").
#  Levanta la app con su docker-compose ENDURECIDO real, prueba la API y comprueba
#  que un modelo .pth malicioso (con código dentro) NO se ejecuta.
#  Recibe $IMAGEN: la imagen recién construida.
# ==============================================================================
set -euo pipefail
# shellcheck source=../_comun.sh
source "$(dirname "${BASH_SOURCE[0]}")/../_comun.sh"     # Docker/Compose con o sin sudo; se sitúa en la raíz
D=("${DOCKER[@]}")
IMAGEN="${IMAGEN:?falta la variable IMAGEN}"
PUERTO_PRUEBAS="${PUERTO_PRUEBAS:-15055}"
PROYECTO="voces-tts-ci"

limpiar() {
    IMAGE="$IMAGEN" PORT="$PUERTO_PRUEBAS" "${COMPOSE[@]}" -p "$PROYECTO" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap limpiar EXIT
limpiar

IMAGE="$IMAGEN" PORT="$PUERTO_PRUEBAS" "${COMPOSE[@]}" -p "$PROYECTO" up -d --no-build
BASE="http://127.0.0.1:$PUERTO_PRUEBAS"
for _ in $(seq 1 90); do curl -sf "$BASE/health" >/dev/null 2>&1 && break; sleep 1; done
bash tests/smoke.sh "$BASE"

echo "▶ Modelos maliciosos (.pth con código)"
"${D[@]}" run --rm --read-only --tmpfs /tmp --cap-drop ALL --network none --entrypoint python3 \
    -v "$PWD/tests:/tests:ro,z" "$IMAGEN" /tests/test_seguridad_modelos.py
