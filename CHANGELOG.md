# CHANGELOG

## [1.0.0] — Construcción por fases

### Fase 1
- Creación del repositorio privado en GitHub

### Fase 2
- Estructura de directorios base
- Template de configuración `settings.env.example`

### Fase 3
- Instalador principal `setup.sh`
- Soporte para ZRAM, swappiness, directorios del sistema

### Fase 4
- Motor de polling `scripts/poller.sh`
- Integración con GitHub Issues API
- flock para ejecución secuencial exclusiva
- timeout + ulimit para protección de recursos

### Fase 5
- Código fuente del executor en Go (`src/mcp-executor/main.go`)
- Herramientas: run_shell, file_read, file_write, system_status
- Script de compilación `scripts/build-executor.sh`

### Fase 6
- Servicio systemd `mcp-node.service` (oneshot, 512MB máx)
- Timer systemd `mcp-node.timer` (cada 20 segundos)
- Script de instalación `scripts/install-systemd.sh`

### Fase 7
- README completo con instalación, configuración y arquitectura
- CHANGELOG

### Fase 8
- Validación end-to-end del flujo completo
