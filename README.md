# claude-code-statusline

[![CI](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml)
[![CodeQL](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE)

Barra de estado personalizada de 3 líneas para [Claude Code](https://claude.com/claude-code):

1. Modelo y esfuerzo · proyecto · rama git (↑ahead ↓behind) · estado git · PR
2. Contexto · límites de uso 5h/7d con cuenta atrás · coste y ritmo $/h · caché de prompt con hora de caducidad · tokens · duración · líneas
3. Todos los ficheros cambiados respecto a `HEAD`. **Cmd+clic** en uno abre su diff en el navegador.

If the prompt cache expires while the context is large, a warning line shows the estimated cost of re-caching it (the price can be adjusted with `STATUSLINE_RECACHE_USD_PER_MTOK`).

El enlace `ⓘ ayuda` abre una leyenda con el significado de cada símbolo.

## Requisitos

- macOS (usa `stty -f` y `ps`; en Linux habría que adaptar `term_width`)
- `bash`, `jq`, `git`, `nc` (netcat) y `python3`
- Una terminal con enlaces OSC 8 (iTerm2, Ghostty, WezTerm, Kitty, VS Code…)

## Instalación

```bash
git clone https://github.com/dMartinezAyuso/claude-code-statusline.git ~/.claude/statusline
cd ~/.claude/statusline
git checkout "$(git describe --tags --abbrev=0)"   # opcional: última versión estable en vez de main
./install.sh                                       # configura statusLine en ~/.claude/settings.json
```

`install.sh` comprueba las dependencias (`./statusline.sh --doctor`), hace **copia de seguridad** de `settings.json`, no pisa un `statusLine` ajeno salvo que uses `--force`, y se deshace con `./install.sh --uninstall`. Si usas otra carpeta de configuración, define `CLAUDE_CONFIG_DIR`.

Instalación manual: en `settings.json`

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline/statusline.sh", "refreshInterval": 10 }
}
```

Se probó con el JSON de statusline de Claude Code de noviembre de 2026. Los campos que no existan simplemente no se pintan.

## Actualizar

```bash
cd ~/.claude/statusline
git pull --ff-only          # última versión
# o, para fijar una versión concreta y estable:
git fetch --tags && git checkout vX.Y.Z   # ver la última en Releases
```

No hace falta reiniciar nada: en el siguiente refresco (≤10 s) `statusline.sh` detecta que `diffserver.py` ha cambiado y reinicia el servidor con el código nuevo. El token se conserva.

Antes de actualizar, mira el [CHANGELOG](CHANGELOG.md): los cambios de seguridad van marcados con **[seguridad]**. Para enterarte de nuevas versiones usa *Watch → Custom → Releases* en GitHub.

## Buenas prácticas de uso

- **Fija una versión** (`git checkout vX.Y.Z`) si prefieres estabilidad; sigue `main` si quieres lo último.
- **Lee el diff antes de actualizar** (`git diff HEAD..origin/main`): este script se ejecuta cada pocos segundos con tus permisos y lanza un servidor. Es poco código; revísalo como harías con cualquier script de terceros.
- **No cambies el puerto a una IP distinta de `127.0.0.1`** ni expongas el servidor con túneles o proxies: serviría tu código sin commitear a quien llegue.
- **No compartas capturas ni copies enlaces de la barra** (llevan el token en la URL). Si lo haces, rota el token (abajo).
- **Rota el token** si sospechas que se ha filtrado: `rm ~/.local/state/claude-code-statusline/token`; se genera otro en el siguiente refresco y el servidor lo lee en cada petición.
- **Para parar el servidor**: `pkill -f diffserver.py`; se relanza solo al volver a usar la barra. Para desactivarlo del todo, quita el statusline de `settings.json`.
- **Personaliza en un fork o rama propia**, no sobre `main` clonado, para que `git pull` no choque con tus cambios.

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

¿Encuentras una vulnerabilidad? Usa el [aviso privado](https://github.com/dMartinezAyuso/claude-code-statusline/security/advisories/new) (ver [SECURITY.md](SECURITY.md)), no un issue público.

## Contribuir

Las PR son bienvenidas: lee [CONTRIBUTING.md](CONTRIBUTING.md). La CI ejecuta shellcheck, las pruebas y CodeQL en cada PR.

## Licencia

MIT
