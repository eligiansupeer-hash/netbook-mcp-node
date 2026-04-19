# netbook-mcp-node

Nodo ejecutor MCP de bajos recursos para netbook Linux con Intel Atom N2600 y 2GB RAM.

## ¿Qué es esto?

Un sistema que convierte una netbook vieja en un ejecutor de tareas controlado por Claude (IA).

Claude crea Issues en este repositorio → La netbook los detecta → Los ejecuta → Devuelve el resultado.

## Hardware soportado

| Componente | Mínimo |
|---|---|
| CPU | Intel Atom N2600 (1.6GHz) o superior |
| RAM | 2GB |
| Almacenamiento | HDD 5400rpm o superior |
| OS | Debian 12 Bookworm (headless) |
| Conectividad | WiFi o Ethernet |

## Instalación rápida

```bash
# En la netbook Linux
git clone https://github.com/eligiansupeer-hash/netbook-mcp-node
cd netbook-mcp-node
cp config/settings.env.example config/settings.env
nano config/settings.env   # Completar GITHUB_TOKEN, GITHUB_USER, GITHUB_REPO
bash setup.sh
```

## Configuración

Editar `config/settings.env`:

```bash
GITHUB_TOKEN="ghp_tu_token_aqui"
GITHUB_USER="tu_usuario"
GITHUB_REPO="netbook-mcp-node"
TASK_LABEL="mcp-cmd"
POLL_INTERVAL=20
TASK_TIMEOUT=120
```

## Cómo enviar una tarea

Crear un Issue en este repositorio con:
- Etiqueta: `mcp-cmd`
- Cuerpo: JSON-RPC 2.0

Ejemplo de cuerpo del Issue:

```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "method": "tools/call",
  "params": {
    "name": "run_shell",
    "arguments": {
      "command": "df -h && free -m"
    }
  }
}
```

## Herramientas disponibles

| Herramienta | Descripción |
|---|---|
| `run_shell` | Ejecuta un comando bash |
| `file_read` | Lee un archivo del sistema |
| `file_write` | Escribe un archivo en /tmp o /home |
| `system_status` | Estado de memoria, CPU y disco |

## Comandos útiles

```bash
# Ver estado del servicio
sudo systemctl status mcp-node.timer

# Ver logs en tiempo real
sudo journalctl -u mcp-node -f

# Ejecutar manualmente un ciclo de polling
mcp-poller

# Detener el nodo
sudo systemctl stop mcp-node.timer

# Reiniciar el nodo
sudo systemctl restart mcp-node.timer
```

## Arquitectura

```
[Claude en la nube]
        |
        | Crea GitHub Issue con JSON-RPC
        v
[GitHub Issues API]
        |
        | Polling cada 20s (curl + jq)
        v
[netbook Linux — Atom N2600]
  ├── systemd timer → poller.sh
  ├── poller.sh → detecta Issue → marca "procesando"
  ├── mcp-executor → ejecuta herramienta
  └── resultado → cierra Issue con comentario
```

## Fases de construcción

- [x] Fase 1: Repositorio GitHub
- [x] Fase 2: Estructura base
- [x] Fase 3: Script setup.sh
- [x] Fase 4: Motor poller.sh
- [x] Fase 5: Executor Go (mcp-executor)
- [x] Fase 6: Configuración systemd
- [x] Fase 7: Documentación
- [ ] Fase 8: Validación end-to-end
