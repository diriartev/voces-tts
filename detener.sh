#!/usr/bin/env bash
# Apaga el contenedor y libera toda la RAM/CPU
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_comun.sh"
"${COMPOSE[@]}" down
echo "✅ Contenedor detenido (0 recursos consumidos)."
