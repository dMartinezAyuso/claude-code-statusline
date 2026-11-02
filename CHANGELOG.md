# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado [SemVer](https://semver.org/lang/es/).
Los cambios de seguridad se marcan con **[seguridad]**.

## [Sin publicar]

## [0.1.0] - 2026-11-02
### Añadido
- Barra de estado de 3 líneas (modelo, git, consumo, límites 5h/7d, ficheros cambiados).
- Servidor local de diffs (`diffserver.py`) con enlaces clicables y página de ayuda.
- Reinicio automático del servidor cuando cambia su código tras una actualización.
### Seguridad
- **[seguridad]** Token aleatorio obligatorio en cada petición (permisos 600, comparación en tiempo constante).
- **[seguridad]** Validación de la cabecera `Host` contra DNS rebinding.
- **[seguridad]** Cabeceras CSP, `nosniff` y `no-referrer`.
