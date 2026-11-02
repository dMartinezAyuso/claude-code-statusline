#!/bin/bash
# Imprime las notas de la versión $1 (sin 'v') tomadas de CHANGELOG.md.
set -eu
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
v="${1#v}"
awk -v v="$v" '
  $0 ~ "^## \\[" v "\\]" { dentro=1; next }
  dentro && /^## \[/ { exit }
  dentro { print }
' "$RAIZ/CHANGELOG.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
