#!/bin/bash
# Prints the notes of version $1 (without 'v') taken from CHANGELOG.md.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
v="${1#v}"
awk -v v="$v" '
  $0 ~ "^## \\[" v "\\]" { inside=1; next }
  inside && /^## \[/ { exit }
  inside { print }
' "$ROOT/CHANGELOG.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
