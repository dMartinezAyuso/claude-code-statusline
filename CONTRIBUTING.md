# Contribuir

## Flujo de cambios
1. Haz fork o crea una rama: `git switch -c fix/lo-que-sea` (`feat/…`, `docs/…`, `ci/…`).
2. Cambia y **prueba en local** (ver abajo).
3. Añade una línea en `CHANGELOG.md` bajo `[Sin publicar]` (marca **[seguridad]** si procede).
4. Abre una PR contra `main`; la plantilla te guía. La CI debe quedar en verde (lint, pruebas en Linux y macOS, CodeQL).
5. Se hace *squash and merge*. El título de la PR pasa a ser el mensaje del commit: que sea claro.

Normas: sin dependencias externas (solo biblioteca estándar y utilidades del sistema), mensajes y documentación en español, cambios pequeños y enfocados.

## Pruebas en local
```bash
bash -n statusline.sh install.sh scripts/*.sh
shellcheck -S warning statusline.sh install.sh scripts/*.sh tests/test_statusline.sh   # pip install shellcheck-py
python3 -m unittest discover -s tests -v     # servidor: token, Host, escapado, límites…
bash tests/test_statusline.sh                # barra completa con estado y puerto temporales
./scripts/check-version.sh                   # VERSION coherente con CHANGELOG
```
Si tocas el servidor, estos comportamientos **no pueden cambiar**: sin token → 403, token incorrecto → 403, `Host` ajeno → 403 aunque el token sea bueno, nombres de fichero escapados en el HTML.
Cada fallo corregido debería llevar una prueba que falle sin el arreglo.

## Versiones (SemVer)
- **Parche** `0.1.1`: arreglos y mejoras internas.
- **Menor** `0.2.0`: funciones nuevas compatibles.
- **Mayor** `1.0.0`: cambia la instalación, las variables de entorno o el formato del estado.

`VERSION` es la fuente de verdad; `scripts/check-version.sh` exige que sea SemVer y que `CHANGELOG.md` tenga su entrada `## [X.Y.Z] - AAAA-MM-DD`.

## Publicar una versión (mantenedor)
```bash
# 1. En una rama: sube VERSION y renombra [Sin publicar] → [X.Y.Z] - fecha en el CHANGELOG
echo X.Y.Z > VERSION
./scripts/check-version.sh                 # debe decir OK
# 2. PR → CI verde → merge a main
# 3. Etiqueta desde main actualizado
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
```
Al subir el tag, el workflow **Release** comprueba que el tag coincide con `VERSION` y con el CHANGELOG, pasa las pruebas, genera el tarball con `SHA256SUMS` y publica la release con las notas del CHANGELOG. No se crea a mano.

Si una release sale mal: no reescribas el tag. Corrígelo con una versión parche nueva.

## Antes de subir: revisión de secretos
```bash
git diff --cached | grep -niE "gho_|ghp_|sk-|password|/Users/"
```
El token real vive en `~/.local/state/claude-code-statusline/`, fuera del repo: nunca debe aparecer en un commit. GitHub tiene activados el escaneo de secretos y la protección de push.
