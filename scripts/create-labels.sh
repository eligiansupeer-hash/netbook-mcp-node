#!/bin/bash
# =============================================================
# create-labels.sh — Crea las etiquetas requeridas en GitHub
# Ejecutar UNA SOLA VEZ desde cualquier máquina con curl
# Uso: bash scripts/create-labels.sh
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/settings.env"

# Cargar configuración si existe
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Verificar variables requeridas
if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_REPO" ]; then
    echo "[ERROR] Definir GITHUB_TOKEN, GITHUB_USER y GITHUB_REPO"
    echo "  Opción 1: Completar config/settings.env"
    echo "  Opción 2: Exportar variables antes de ejecutar:"
    echo "    export GITHUB_TOKEN=ghp_xxx GITHUB_USER=usuario GITHUB_REPO=netbook-mcp-node"
    exit 1
fi

GITHUB_API="https://api.github.com"
REPO_PATH="/repos/${GITHUB_USER}/${GITHUB_REPO}/labels"

create_label() {
    local name="$1"
    local color="$2"
    local description="$3"

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "${GITHUB_API}${REPO_PATH}" \
        -d "{\"name\":\"${name}\",\"color\":\"${color}\",\"description\":\"${description}\"}")

    if [ "$response" = "201" ]; then
        echo "[OK] Etiqueta creada: $name"
    elif [ "$response" = "422" ]; then
        echo "[INFO] Etiqueta ya existe: $name (omitiendo)"
    else
        echo "[WARN] Respuesta inesperada para '$name': HTTP $response"
    fi
}

echo "[INFO] Creando etiquetas en ${GITHUB_USER}/${GITHUB_REPO}..."
echo ""

create_label "mcp-cmd"    "e4610f" "Tarea para el nodo MCP"
create_label "procesando" "fbca04" "Tarea en ejecucion por el nodo"

echo ""
echo "[OK] Listo. Verificar en:"
echo "  https://github.com/${GITHUB_USER}/${GITHUB_REPO}/labels"
