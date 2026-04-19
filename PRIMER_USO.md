# PRIMER USO — Guía de arranque rápido

> Esta guía asume que ya tenés Debian 12 instalado en la netbook y el repo clonado.

---

## Paso 0: Clonar el repo

```bash
git clone https://github.com/eligiansupeer-hash/netbook-mcp-node
cd netbook-mcp-node
```

## Paso 1: Instalar dependencias base

```bash
sudo apt update && sudo apt install -y curl jq git golang
```

## Paso 2: Configurar credenciales

```bash
cp config/settings.env.example config/settings.env
nano config/settings.env
```

Completar estas variables (las demás tienen valores por defecto):

```bash
GITHUB_TOKEN="ghp_TU_TOKEN_REAL"   # Personal Access Token con scope 'repo'
GITHUB_USER="eligiansupeer-hash"    # Tu usuario de GitHub
GITHUB_REPO="netbook-mcp-node"
```

> Para crear un token: GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained → scope: Issues (read/write) + Contents (read)

## Paso 3: Compilar el executor

```bash
bash scripts/build-executor.sh
```

Resultado esperado:
```
[OK] Binario compilado: bin/mcp-executor
[OK] Binario estático confirmado
```

## Paso 4: Ejecutar el instalador

```bash
bash setup.sh
```

El instalador hace automáticamente:
- Instala dependencias apt
- Configura ZRAM (1GB swap en RAM)
- Crea directorios del sistema
- Copia poller y executor a `/usr/local/bin/`
- Instala y activa el servicio systemd

## Paso 5: Crear las etiquetas en GitHub

Ejecutar este script **una sola vez** desde la netbook (reemplaza TU_TOKEN y TU_USUARIO):

```bash
GITHUB_TOKEN="ghp_TU_TOKEN"
GITHUB_USER="eligiansupeer-hash"
GITHUB_REPO="netbook-mcp-node"

# Crear etiqueta mcp-cmd (naranja)
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/labels \
  -d '{"name":"mcp-cmd","color":"e4610f","description":"Tarea para el nodo MCP"}'

# Crear etiqueta procesando (amarillo)
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/labels \
  -d '{"name":"procesando","color":"fbca04","description":"Tarea en ejecucion"}'

echo "Etiquetas creadas"
```

## Paso 6: Verificar que todo funciona

```bash
# Timer activo
sudo systemctl status mcp-node.timer

# Ver logs en vivo
sudo journalctl -u mcp-node -f
```

## Paso 7: Test manual (Fase 8)

Desde Windows/Claude, crear un Issue con:
- **Título**: `[TEST] system_status`
- **Etiqueta**: `mcp-cmd`
- **Cuerpo**:

```json
{
  "jsonrpc": "2.0",
  "id": "test-001",
  "method": "tools/call",
  "params": {
    "name": "system_status",
    "arguments": {}
  }
}
```

En menos de 60 segundos el Issue debería cerrarse con un comentario mostrando el estado del sistema.

---

## Troubleshooting rápido

| Síntoma | Causa probable | Solución |
|---|---|---|
| Timer inactivo | `setup.sh` no completó | Correr `bash scripts/install-systemd.sh` |
| Issue no se procesa | Token sin permisos | Regenerar token con scope `repo` |
| `mcp-executor` no encontrado | Compilación no corrió | `bash scripts/build-executor.sh` |
| Lock file atascado | Crash anterior | `rm -f /tmp/mcp-poller.lock` |
| Sin conectividad GitHub | Red caída | `ping 8.8.8.8` y revisar WiFi |

---

## Parámetros del kernel recomendados (anti-freeze Atom N2600)

En `/etc/default/grub`:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_idle.max_cstate=1"
```
Luego: `sudo update-grub && sudo reboot`

---

*netbook-mcp-node v1.0.0 — Fénix MCP Node*
