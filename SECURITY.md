# Política de seguridad

## Versiones con soporte
Solo la última versión publicada (última etiqueta / `main`). Los arreglos de seguridad salen como versión **parche** y se marcan **[seguridad]** en el [CHANGELOG](CHANGELOG.md).

## Cómo reportar una vulnerabilidad
Usa el **[aviso privado de GitHub](https://github.com/dMartinezAyuso/claude-code-statusline/security/advisories/new)** (Security → Report a vulnerability). Por favor, no abras un issue público con los detalles hasta que haya arreglo.
Es un proyecto personal sin plazos garantizados; intento responder en unos días y coordinar la publicación contigo.

## Modelo de amenaza
Protege frente a **páginas web maliciosas** que intenten leer tus diffs a través de `127.0.0.1` (token + validación de `Host`).
**No** protege frente a otro usuario con acceso a tu cuenta o a tu máquina: el token está en un fichero de tu usuario y en las URL de la terminal.

## Medidas de la cadena de suministro
- Sin dependencias externas (solo biblioteca estándar de Python y utilidades del sistema).
- Acciones de GitHub fijadas por SHA, actualizadas por Dependabot.
- Workflows con permisos mínimos (`contents: read`; solo la release tiene `contents: write`).
- CodeQL semanal y en cada PR; secret scanning y push protection activados.
- Cada release incluye `SHA256SUMS` del tarball.
