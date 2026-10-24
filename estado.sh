#!/usr/bin/env bash
# Muestra si el servicio está activo y cuántas voces tiene
source "$(dirname "${BASH_SOURCE[0]}")/_comun.sh"
"${COMPOSE[@]}" ps
if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    echo "🌐 http://127.0.0.1:$PORT"; curl -s "http://127.0.0.1:$PORT/health"; echo
else
    echo "🔴 El servicio no responde en http://127.0.0.1:$PORT"
fi
