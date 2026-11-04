#!/bin/bash
# Fails if VERSION is not SemVer or CHANGELOG.md has no entry for that version.
# With an argument (e.g. the tag v1.2.3) it also checks that it matches VERSION.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
v=$(tr -d '[:space:]' <"$ROOT/VERSION")
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION is not SemVer: '$v'" >&2; exit 1; }
grep -qE "^## \[$v\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$ROOT/CHANGELOG.md" \
  || { echo "CHANGELOG.md has no entry '## [$v] - YYYY-MM-DD'" >&2; exit 1; }
if [ -n "${1:-}" ] && [ "${1#v}" != "$v" ]; then
  echo "Tag '$1' does not match VERSION ($v)" >&2; exit 1
fi
echo "OK version $v"
