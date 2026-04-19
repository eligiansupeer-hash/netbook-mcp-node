#!/bin/bash
# =============================================================
# setup.sh — Instalador del Nodo MCP para Netbook Linux
# Hardware objetivo: Intel Atom N2600, 2GB RAM, HDD
# Sistema operativo: Debian 12 Bookworm (headless)
# Uso: bash setup.sh
# =============================================================
set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_info() { echo -e "[INFO] $1"; }

# =============================================================
# VERIFICACIONES PREVIAS
# =============================================================

log_info "=== Instalador del Nodo MCP — Netbook Linux ==="
log_info "Verificando prerrequisitos..."

# Verificar que no sea root (se pedirá sudo cuando sea necesario)
if [ "$EUID" -eq 0 ]; then
    log_err "No ejecutar como root. Usa un usuario normal con sudo."
fi

# Verificar sistema operativo
if ! grep -q "Debian" /etc/os-release 2>/dev/null; then
    log_warn "Este instalador está optimizado para Debian 12. Continuando de todas formas."
fi

# Verificar herramientas base
for tool in curl jq git sudo systemctl; do
    if ! command -v "$tool" &>/dev/null; then
        log_err "Herramienta requerida no encontrada: $tool. Instalar con: sudo apt install $tool"
    fi
done
log_ok "Herramientas base verificadas: curl, jq, git, sudo, systemctl"

# Verificar archivo de configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/settings.env"

if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "No se encontró config/settings.env"
    log_info "Copiando template..."
    cp "$SCRIPT_DIR/config/settings.env.example" "$CONFIG_FILE"
    log_err "Editar $CONFIG_FILE con tus credenciales y volver a ejecutar setup.sh"
fi

# Cargar configuración
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Verificar variables críticas
for var in GITHUB_TOKEN GITHUB_USER GITHUB_REPO; do
    if [ -z "${!var}" ] || echo "${!var}" | grep -q "XXXXX"; then
        log_err "Variable $var no configurada en config/settings.env"
    fi
done
log_ok "Configuración cargada correctamente"

# =============================================================
# PASO 1: INSTALAR DEPENDENCIAS DEL SISTEMA
# =============================================================

log_info "--- Paso 1: Instalando dependencias ---"

sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    curl \
    jq \
    git \
    util-linux \
    procps \
    2>/dev/null

log_ok "Dependencias instaladas"

# =============================================================
# PASO 2: CONFIGURAR ZRAM (MEMORIA VIRTUAL EN RAM)
# =============================================================

log_info "--- Paso 2: Configurando ZRAM ---"

if ! lsmod | grep -q zram; then
    sudo modprobe zram num_devices=1
fi

ZRAM_SIZE="1073741824"  # 1GB en bytes

if [ -f /sys/block/zram0/disksize ]; then
    # Resetear si ya estaba configurado
    if grep -q "zram0" /proc/swaps 2>/dev/null; then
        sudo swapoff /dev/zram0 2>/dev/null || true
        echo 1 | sudo tee /sys/block/zram0/reset > /dev/null
    fi
    echo "zstd" | sudo tee /sys/block/zram0/comp_algorithm > /dev/null 2>&1 || \
    echo "lz4" | sudo tee /sys/block/zram0/comp_algorithm > /dev/null
    echo "$ZRAM_SIZE" | sudo tee /sys/block/zram0/disksize > /dev/null
    sudo mkswap /dev/zram0 -q
    sudo swapon /dev/zram0 -p 100
    log_ok "ZRAM configurado (1GB, algoritmo: zstd/lz4)"
else
    log_warn "ZRAM no disponible en este kernel. Continuando sin él."
fi

# Ajustar swappiness para minimizar uso del HDD
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p > /dev/null 2>&1
log_ok "swappiness configurado a 10"

# =============================================================
# PASO 3: CREAR DIRECTORIOS DEL SISTEMA
# =============================================================

log_info "--- Paso 3: Creando directorios del sistema ---"

LOG_DIR="${LOG_DIR:-/var/log/mcp-node}"
QUEUE_DIR="${QUEUE_DIR:-/var/lib/mcp-node/queue}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"

sudo mkdir -p "$LOG_DIR"
sudo mkdir -p "$QUEUE_DIR"
sudo chown "$USER:$USER" "$LOG_DIR"
sudo chown "$USER:$USER" "$QUEUE_DIR"
log_ok "Directorios creados: $LOG_DIR, $QUEUE_DIR"

# =============================================================
# PASO 4: INSTALAR SCRIPTS
# =============================================================

log_info "--- Paso 4: Instalando scripts ---"

sudo cp "$SCRIPT_DIR/scripts/poller.sh" /usr/local/bin/mcp-poller
sudo chmod +x /usr/local/bin/mcp-poller
log_ok "Script poller instalado en /usr/local/bin/mcp-poller"

# =============================================================
# PASO 5: INSTALAR BINARIO MCP-EXECUTOR
# =============================================================

log_info "--- Paso 5: Instalando binario mcp-executor ---"

if [ -f "$SCRIPT_DIR/bin/mcp-executor" ]; then
    sudo cp "$SCRIPT_DIR/bin/mcp-executor" /usr/local/bin/mcp-executor
    sudo chmod +x /usr/local/bin/mcp-executor
    log_ok "Binario mcp-executor instalado"
else
    log_warn "Binario mcp-executor no encontrado. Se instalará en Fase 5."
fi

# =============================================================
# PASO 6: INSTALAR SERVICIO SYSTEMD
# =============================================================

log_info "--- Paso 6: Configurando servicio systemd ---"

INSTALL_SYSTEMD="$SCRIPT_DIR/scripts/install-systemd.sh"

if [ -f "$INSTALL_SYSTEMD" ]; then
    bash "$INSTALL_SYSTEMD"
    log_ok "Servicio systemd habilitado e iniciado"
else
    log_warn "scripts/install-systemd.sh no encontrado."
    log_warn "Ejecutar manualmente tras completar Fase 6 del repositorio:"
    log_warn "  bash \$SCRIPT_DIR/scripts/install-systemd.sh"
fi

# =============================================================
# PASO 7: CREAR ARCHIVO DE CONFIGURACIÓN DE RUNTIME
# =============================================================

log_info "--- Paso 7: Configurando runtime ---"

# Copiar settings al directorio del sistema
sudo mkdir -p /etc/mcp-node
sudo cp "$CONFIG_FILE" /etc/mcp-node/settings.env
sudo chmod 600 /etc/mcp-node/settings.env

log_ok "Configuración copiada a /etc/mcp-node/settings.env"

# =============================================================
# VERIFICACIÓN FINAL
# =============================================================

log_info "--- Verificación final ---"

echo ""
echo "Estado del sistema:"

systemctl is-active mcp-node.timer &>/dev/null && \
    log_ok "Timer systemd: ACTIVO" || \
    log_warn "Timer systemd: INACTIVO (normal si es primera instalación)"

[ -x /usr/local/bin/mcp-poller ] && \
    log_ok "Script poller: INSTALADO" || \
    log_err "Script poller: NO ENCONTRADO"

[ -x /usr/local/bin/mcp-executor ] && \
    log_ok "Binario executor: INSTALADO" || \
    log_warn "Binario executor: PENDIENTE (completar Fase 5)"

echo ""
log_ok "=== Setup completado ==="
log_info "El nodo comenzará a procesar tareas automáticamente."
log_info "Ver logs: sudo journalctl -u mcp-node -f"
log_info "Estado: sudo systemctl status mcp-node.timer"
