# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado [SemVer](https://semver.org/lang/es/).
Los cambios de seguridad se marcan con **[seguridad]**.

## [Sin publicar]

## [0.1.0] - 2026-11-02
### Añadido
- Barra de estado de 3 líneas (modelo, git, consumo, límites 5h/7d, ficheros cambiados).
- Servidor local de diffs (`diffserver.py`) con enlaces clicables y página de ayuda (muestra la versión).
- Reinicio automático del servidor cuando cambia su código tras una actualización.
- `install.sh` (instala/desinstala en `settings.json` con copia de seguridad) y `statusline.sh --doctor` / `--version`.
- Pruebas automáticas (servidor y barra) y CI en Linux y macOS (Python 3.9–3.13).
- Release automatizada al subir un tag `vX.Y.Z` (notas desde este fichero, tarball y SHA256SUMS).
- CodeQL, Dependabot, plantillas de PR e issues y política de seguridad.
### Corregido
- Los conflictos de merge `AA` y `DD` se pintaban como añadido/borrado en lugar de conflicto.
### Seguridad
- **[seguridad]** Token aleatorio obligatorio en cada petición (permisos 600, comparación en tiempo constante).
- **[seguridad]** Validación de la cabecera `Host` contra DNS rebinding.
- **[seguridad]** Cabeceras CSP, `nosniff` y `no-referrer`.
- **[seguridad]** Tiempo máximo por llamada a `git` (10 s) y tope de 512 KiB por diff para evitar cuelgues y consumo de memoria.
- **[seguridad]** Acciones de GitHub fijadas por SHA y permisos mínimos en los workflows.
