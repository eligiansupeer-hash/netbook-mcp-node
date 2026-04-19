#!/bin/bash
# install-systemd.sh — Instala los servicios systemd del nodo MCP
# Ejecutar como usuario normal con sudo disponible

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_SRC="$SCRIPT_DIR/../systemd"
CURRENT_USER=$(whoami)

echo "[INFO] Instalando servicios systemd para usuario: $CURRENT_USER"

# Reemplazar RUNTIME_USER con el usuario actual en el archivo de servicio
sed "s/RUNTIME_USER/$CURRENT_USER/g" "$SYSTEMD_SRC/mcp-node.service" | \
    sudo tee /etc/systemd/system/mcp-node.service > /dev/null

sudo cp "$SYSTEMD_SRC/mcp-node.timer" /etc/systemd/system/mcp-node.timer

sudo systemctl daemon-reload

sudo systemctl enable mcp-node.timer
sudo systemctl start mcp-node.timer

echo "[OK] Timer instalado y activo"
echo ""
echo "Comandos útiles:"
echo "  sudo systemctl status mcp-node.timer"
echo "  sudo systemctl status mcp-node.service"
echo "  sudo journalctl -u mcp-node -f"
echo "  sudo systemctl stop mcp-node.timer   # para detener"
