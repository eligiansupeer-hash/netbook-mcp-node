#!/bin/bash
# =============================================================
# poller.sh — Motor de Polling y Ejecución de Tareas MCP
# Consulta GitHub Issues, extrae tareas MCP y las ejecuta
# Diseñado para: Intel Atom N2600, 2GB RAM, Debian 12
# =============================================================

# Cargar configuración
CONFIG_FILE="${MCP_CONFIG:-/etc/mcp-node/settings.env}"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Archivo de configuración no encontrado: $CONFIG_FILE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Configuración con valores por defecto
GITHUB_API="https://api.github.com"
TASK_LABEL="${TASK_LABEL:-mcp-cmd}"
PROCESSING_LABEL="${PROCESSING_LABEL:-procesando}"
TASK_TIMEOUT="${TASK_TIMEOUT:-120}"
LOG_DIR="${LOG_DIR:-/var/log/mcp-node}"
QUEUE_DIR="${QUEUE_DIR:-/var/lib/mcp-node/queue}"
LOCK_FILE="/tmp/mcp-poller.lock"
EXECUTOR_BIN="${EXECUTOR_BIN:-/usr/local/bin/mcp-executor}"

# =============================================================
# FUNCIONES AUXILIARES
# =============================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_DIR/poller.log" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] $1"
}

log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_DIR/poller.log" 2>/dev/null
    echo "[ERROR] $1" >&2
}

# Llamada a la API de GitHub
github_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${GITHUB_API}${endpoint}" 2>/dev/null
    else
        curl -s -X "$method" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "${GITHUB_API}${endpoint}" 2>/dev/null
    fi
}

# Obtener el Issue más antiguo con etiqueta mcp-cmd (y sin "procesando")
get_pending_issue() {
    github_api GET \
        "/repos/${GITHUB_USER}/${GITHUB_REPO}/issues?labels=${TASK_LABEL}&state=open&sort=created&direction=asc&per_page=1" \
    | jq -r '
        .[] |
        select(
            (.labels | map(.name) | index("procesando")) == null
        ) |
        {id: .number, title: .title, body: .body} |
        @base64
    ' 2>/dev/null | head -1
}

# Marcar Issue como "procesando"
mark_processing() {
    local issue_number="$1"
    github_api POST \
        "/repos/${GITHUB_USER}/${GITHUB_REPO}/issues/${issue_number}/labels" \
        "{\"labels\":[\"${PROCESSING_LABEL}\"]}" > /dev/null
    log "Issue #${issue_number}: marcado como 'procesando'"
}

# Cerrar Issue y agregar comentario con resultado
close_issue_with_result() {
    local issue_number="$1"
    local result_body="$2"

    # Agregar comentario con resultado
    local escaped_result
    escaped_result=$(echo "$result_body" | jq -Rs '.')
    github_api POST \
        "/repos/${GITHUB_USER}/${GITHUB_REPO}/issues/${issue_number}/comments" \
        "{\"body\":${escaped_result}}" > /dev/null

    # Cerrar el issue
    github_api PATCH \
        "/repos/${GITHUB_USER}/${GITHUB_REPO}/issues/${issue_number}" \
        '{"state":"closed"}' > /dev/null

    log "Issue #${issue_number}: cerrado con resultado"
}

# =============================================================
# FUNCIÓN PRINCIPAL DE EJECUCIÓN
# =============================================================

execute_task() {
    local issue_number="$1"
    local task_body="$2"

    log "Ejecutando tarea del Issue #${issue_number}"

    # Verificar que el executor existe
    if [ ! -x "$EXECUTOR_BIN" ]; then
        close_issue_with_result "$issue_number" \
            "**ERROR**: Executor no encontrado en $EXECUTOR_BIN. Completar Fase 5 del setup."
        return 1
    fi

    # Preparar archivo temporal en RAM (tmpfs)
    local tmp_output
    tmp_output=$(mktemp /tmp/mcp_output_XXXXXX)
    local tmp_input
    tmp_input=$(mktemp /tmp/mcp_input_XXXXXX)

    # Escribir payload al archivo temporal
    echo "$task_body" > "$tmp_input"

    # Ejecutar con timeout y límite de memoria
    local exit_code=0
    timeout -k 5s "${TASK_TIMEOUT}s" \
        bash -c "ulimit -v 524288; cat '$tmp_input' | '$EXECUTOR_BIN'" \
        > "$tmp_output" 2>&1 || exit_code=$?

    # Leer resultado
    local result
    result=$(cat "$tmp_output" 2>/dev/null || echo "Sin salida")

    # Limpiar temporales
    rm -f "$tmp_output" "$tmp_input"

    # Construir respuesta
    local status_msg
    if [ "$exit_code" -eq 0 ]; then
        status_msg="✅ ÉXITO (exit code: 0)"
    elif [ "$exit_code" -eq 124 ]; then
        status_msg="⏱️ TIMEOUT (límite: ${TASK_TIMEOUT}s)"
        result="La tarea superó el tiempo límite de ${TASK_TIMEOUT} segundos."
    else
        status_msg="❌ ERROR (exit code: ${exit_code})"
    fi

    local response_body="**Estado**: ${status_msg}

\`\`\`
${result}
\`\`\`

*Ejecutado: $(date '+%Y-%m-%d %H:%M:%S') | Nodo: $(hostname)*"

    close_issue_with_result "$issue_number" "$response_body"
    return "$exit_code"
}

# =============================================================
# LOOP PRINCIPAL
# =============================================================

main() {
    # Garantía de ejecución única (flock no bloqueante)
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log "Otra instancia en ejecución. Saliendo."
        exit 0
    fi

    log "=== Ciclo de polling iniciado ==="

    # Verificar conectividad básica
    if ! curl -s --max-time 5 "https://api.github.com" > /dev/null 2>&1; then
        log_err "Sin conectividad con GitHub API. Saliendo."
        exit 0
    fi

    # Buscar tarea pendiente
    local encoded_issue
    encoded_issue=$(get_pending_issue)

    if [ -z "$encoded_issue" ]; then
        log "No hay tareas pendientes."
        exit 0
    fi

    # Decodificar datos del issue
    local issue_data
    issue_data=$(echo "$encoded_issue" | base64 -d 2>/dev/null)
    local issue_number
    issue_number=$(echo "$issue_data" | jq -r '.id')
    local issue_body
    issue_body=$(echo "$issue_data" | jq -r '.body')

    log "Tarea encontrada: Issue #${issue_number}"

    # Marcar como "en proceso" para evitar duplicación
    mark_processing "$issue_number"

    # Ejecutar tarea
    execute_task "$issue_number" "$issue_body"

    log "=== Ciclo completado ==="
}

main "$@"
