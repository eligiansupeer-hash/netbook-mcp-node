# netbook-mcp-node

Nodo ejecutor MCP de bajos recursos para netbook Linux (Intel Atom N2600, 2GB RAM).

## Instalación

```bash
git clone https://github.com/eligiansupeer-hash/netbook-mcp-node
cd netbook-mcp-node
bash setup.sh
```

## Arquitectura

- Orquestador: bash
- Cola: GitHub Issues
- Executor: binario Go estático
- Memoria virtual: zram
- Temporales: tmpfs

## Estado

Fase 1/8 completada.
