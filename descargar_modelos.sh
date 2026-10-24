#!/usr/bin/env bash
# Instala los modelos de voz (.pth/.index) listados en modelos_rvc/checksums.sha256
#
# Para cada <voz>.zip busca, en este orden:
#   1. el zip ya copiado en la carpeta del proyecto o en modelos_rvc/   (sin internet)
#   2. el Release de GitHub de MODELS_REPO (o la URL MODELS_URL)
# Y siempre verifica su SHA-256 antes de instalarlo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f .env ] && { set -a; . ./.env; set +a; }
MODELS_REPO="${MODELS_REPO:-diriartev/voces-tts}"
MODELS_TAG="${MODELS_TAG:-modelos-v1}"
BASE="${MODELS_URL:-https://github.com/$MODELS_REPO/releases/download/$MODELS_TAG}"

for cmd in curl python3 sha256sum; do
    command -v "$cmd" >/dev/null || { echo "❌ Falta '$cmd' (instálalo con apt/dnf)"; exit 1; }
done

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FALLOS=0
while read -r SUM ZIP; do
    [ -z "${ZIP:-}" ] && continue
    NAME="${ZIP%.zip}"
    DEST="modelos_rvc/$NAME"
    if ls "$DEST"/*.pth >/dev/null 2>&1; then
        echo "✔ $NAME ya está instalado"
        continue
    fi

    SRC=""
    for c in "./$ZIP" "modelos_rvc/$ZIP"; do [ -f "$c" ] && SRC="$c" && break; done
    if [ -n "$SRC" ]; then
        echo "📦 Usando $SRC (local)"
    else
        echo "⬇ Descargando $ZIP de $BASE ..."
        if ! curl -fL --retry 3 --progress-bar -o "$TMP/$ZIP" "$BASE/$ZIP"; then
            echo "⚠️  No se pudo descargar $ZIP. Copia el zip en esta carpeta y vuelve a ejecutar."
            FALLOS=1; continue
        fi
        SRC="$TMP/$ZIP"
    fi

    if ! echo "$SUM  $SRC" | sha256sum -c --quiet - 2>/dev/null; then
        echo "❌ $ZIP no coincide con su SHA-256 (archivo dañado o alterado). No se instala."
        FALLOS=1; continue
    fi

    mkdir -p "$DEST"
    # Extrae solo .pth/.index, sin rutas (evita archivos maliciosos dentro del zip)
    python3 - "$SRC" "$DEST" <<'PY'
import sys, zipfile, os, shutil
zf, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zf) as z:
    for m in z.infolist():
        name = os.path.basename(m.filename)
        if name.endswith((".pth", ".index")):
            out_path = os.path.join(dest, name)
            with z.open(m) as src, open(out_path, "wb") as out:
                shutil.copyfileobj(src, out, 1024 * 1024)
            os.chmod(out_path, 0o644)
            print("   ->", out_path)
PY
    echo "✅ $NAME instalado"
done < modelos_rvc/checksums.sha256

if [ "$FALLOS" -eq 0 ]; then
    echo "✅ Modelos listos"
else
    echo "⚠️  Faltan algunos modelos (las demás voces funcionan igual)"
    exit 1
fi
