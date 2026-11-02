# Flujo de cambios y publicación

## Cambios (cualquiera, vía PR)
1. Fork o rama: `git switch -c fix/lo-que-sea`.
2. Cambia y **prueba** (ver abajo).
3. Añade una línea en `CHANGELOG.md` bajo `[Sin publicar]` (con **[seguridad]** si procede).
4. Abre una PR contra `main` describiendo qué y por qué.

## Pruebas mínimas antes de cada PR
```bash
bash -n statusline.sh && python3 -m py_compile diffserver.py && rm -rf __pycache__
# servidor en un puerto y estado de pruebas
S=$(mktemp -d); echo -n abc123 >"$S/token"
STATUSLINE_PORT=18765 STATUSLINE_STATE="$S" python3 diffserver.py &
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:18765/ayuda"                     # 403 (sin token)
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: evil.com:18765" "http://127.0.0.1:18765/ayuda?t=abc123"  # 403
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:18765/ayuda?t=abc123"            # 200
kill %1
```
Si tocas el servidor, esos tres resultados no pueden cambiar. No añadas dependencias externas: solo biblioteca estándar de Python y utilidades básicas de macOS.

## Publicar una versión (mantenedor)
1. Mueve `[Sin publicar]` del CHANGELOG a `[X.Y.Z] - fecha`.
2. Commit en `main`: `git commit -am "Release vX.Y.Z"`.
3. Etiqueta y sube: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin main vX.Y.Z`.
4. Crea la release: `gh release create vX.Y.Z --notes-from-tag` (o pega las notas del CHANGELOG).

SemVer: **parche** = arreglos; **menor** = funciones nuevas compatibles; **mayor** = cambia la instalación, variables de entorno o el formato del estado.

## Revisión de secretos antes de subir
```bash
git diff --cached | grep -niE "token|secret|password|gho_|sk-|/Users/"
```
El token real vive en `~/.local/state/claude-code-statusline/`, fuera del repo: nunca debe aparecer en un commit.
