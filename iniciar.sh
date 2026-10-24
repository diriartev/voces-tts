#!/usr/bin/env bash
# Instala modelos si faltan, construye (la primera vez) y arranca, y abre la web.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_comun.sh"

bash ./descargar_modelos.sh || echo "⚠️  Sigo sin esos modelos: el resto de voces funciona."

echo "🔨 Construyendo/arrancando (la primera vez tarda varios minutos: baja PyTorch y RVC)..."
if [[ "${IMAGE:-}" == ghcr.io/* ]]; then
    # Imagen publicada por el pipeline (probada, escaneada y firmada)
    if command -v cosign >/dev/null 2>&1; then
        echo "🔏 Verificando la firma de $IMAGE ..."
        cosign verify "$IMAGE" \
            --certificate-identity-regexp "^https://github.com/diriartev/voces-tts/.github/workflows/release.yml@refs/tags/" \
            --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null
        echo "✔ Firma válida"
    fi
    "${COMPOSE[@]}" pull
    "${COMPOSE[@]}" up -d --no-build
else
    "${COMPOSE[@]}" up -d --build
fi

echo "Esperando a que responda http://127.0.0.1:$PORT ..."
for _ in {1..90}; do
    if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        echo "✅ Voces TTS activo en http://127.0.0.1:$PORT"
        curl -s "http://127.0.0.1:$PORT/health"; echo
        (xdg-open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true) &
        exit 0
    fi
    sleep 1
done
echo "⚠️  Tardó en responder. Revisa:  ${COMPOSE[*]} logs"
exit 1
