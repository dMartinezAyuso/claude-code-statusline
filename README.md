# claude-code-statusline

Barra de estado personalizada de 3 líneas para [Claude Code](https://claude.com/claude-code):

1. Modelo y esfuerzo · proyecto · rama git (↑ahead ↓behind) · estado git · PR
2. Contexto · límites de uso 5h/7d con cuenta atrás · coste · caché de prompt · tokens · duración · líneas
3. Todos los ficheros cambiados respecto a `HEAD`. **Cmd+clic** en uno abre su diff en el navegador.

El enlace `ⓘ ayuda` abre una leyenda con el significado de cada símbolo.

## Requisitos

- macOS (usa `stty -f` y `ps`; en Linux habría que adaptar `term_width`)
- `bash`, `jq`, `git`, `nc` (netcat) y `python3`
- Una terminal con enlaces OSC 8 (iTerm2, Ghostty, WezTerm, Kitty, VS Code…)

## Instalación

```bash
git clone https://github.com/dMartinezAyuso/claude-code-statusline.git ~/.claude/statusline
```

En `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline/statusline.sh",
    "refreshInterval": 10
  }
}
```

Se probó con el JSON de statusline de Claude Code de noviembre de 2026. Los campos que no existan simplemente no se pintan.

## Qué ejecuta en tu máquina

Conviene saberlo antes de instalar:

- La primera vez que hay un repo git, `statusline.sh` **arranca en segundo plano** `diffserver.py`, un servidor HTTP en `127.0.0.1:8765` (cambiable con `STATUSLINE_PORT`).
- Ese servidor **solo lee**: ejecuta `git status` / `git diff` y pinta HTML. No escribe nada en tus repos.
- Estado y token se guardan en `~/.local/state/claude-code-statusline/` (`XDG_STATE_HOME`).

## Seguridad

El servidor expone el código sin commitear de tus repos, así que está protegido:

- Solo escucha en `127.0.0.1`.
- **Token secreto** de 128 bits generado al azar (fichero con permisos `600`, carpeta `700`), exigido en cada petición y comparado en tiempo constante. Una web cualquiera no puede leer tus diffs aunque adivine el puerto.
- **Validación de `Host`**: se rechaza cualquier petición cuyo `Host` no sea `127.0.0.1:<puerto>` o `localhost:<puerto>` (defensa contra DNS rebinding).
- Cabeceras `Content-Security-Policy`, `X-Content-Type-Options` y `Referrer-Policy`; el contenido se escapa con `html.escape`.
- El parámetro `d=` debe ser un repo git; si no, 400.

El token va en la URL de los enlaces, por lo que quien tenga acceso a tu sesión de terminal podría verlo: es un modelo de amenaza local pensado para evitar accesos desde el navegador, no frente a otro usuario con acceso a tu cuenta. Para rotarlo, borra `~/.local/state/claude-code-statusline/token` y reinicia el servidor (`pkill -f diffserver.py`).

¿Encuentras una vulnerabilidad? Abre un issue o escríbeme.

## Licencia

MIT
