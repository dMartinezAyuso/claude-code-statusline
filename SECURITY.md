# Política de seguridad

## Versiones con soporte
Solo la última versión publicada (`main` / última etiqueta).

## Cómo reportar una vulnerabilidad
Usa **Security → Report a vulnerability** en GitHub (aviso privado). Por favor no abras un issue público con los detalles hasta que haya arreglo.
Intento responder en unos días; este es un proyecto personal, sin plazos garantizados.

## Modelo de amenaza
Protege frente a **páginas web maliciosas** que intenten leer tus diffs a través de `127.0.0.1` (token + validación de `Host`).
**No** protege frente a otro usuario con acceso a tu cuenta o a tu máquina: el token está en un fichero de tu usuario y en las URL de la terminal.
