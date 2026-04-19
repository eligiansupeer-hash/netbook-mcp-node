#!/bin/bash
# build-executor.sh — Compila mcp-executor para Linux x86_64
# Ejecutar en la máquina con Go instalado, luego copiar el binario a bin/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src/mcp-executor"
BIN_DIR="$SCRIPT_DIR/../bin"

echo "[INFO] Compilando mcp-executor..."
echo "[INFO] Directorio fuente: $SRC_DIR"

cd "$SRC_DIR"

# Compilar binario estático para Linux x86_64
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -ldflags="-s -w" \
    -o "$BIN_DIR/mcp-executor" \
    .

echo "[OK] Binario compilado: $BIN_DIR/mcp-executor"
echo "[INFO] Tamaño: $(du -sh "$BIN_DIR/mcp-executor" | cut -f1)"

# Verificar que el binario es estático
if file "$BIN_DIR/mcp-executor" | grep -q "statically linked"; then
    echo "[OK] Binario estático confirmado"
elif file "$BIN_DIR/mcp-executor" | grep -q "ELF"; then
    echo "[WARN] Binario ELF generado (puede requerir libc en target)"
else
    echo "[ERROR] El binario puede no ser ejecutable en Linux"
fi

echo ""
echo "Para instalar en la netbook:"
echo "  cp bin/mcp-executor /usr/local/bin/mcp-executor"
echo "  chmod +x /usr/local/bin/mcp-executor"
