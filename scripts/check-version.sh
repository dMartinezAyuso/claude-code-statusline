#!/bin/bash
# Falla si VERSION no es SemVer o si CHANGELOG.md no tiene la entrada de esa versión.
# Con un argumento (p. ej. el tag v1.2.3) comprueba además que coincide con VERSION.
set -eu
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
v=$(tr -d '[:space:]' <"$RAIZ/VERSION")
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION no es SemVer: '$v'" >&2; exit 1; }
grep -qE "^## \[$v\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$RAIZ/CHANGELOG.md" \
  || { echo "CHANGELOG.md no tiene la entrada '## [$v] - AAAA-MM-DD'" >&2; exit 1; }
if [ -n "${1:-}" ] && [ "${1#v}" != "$v" ]; then
  echo "El tag '$1' no coincide con VERSION ($v)" >&2; exit 1
fi
echo "OK versión $v"
