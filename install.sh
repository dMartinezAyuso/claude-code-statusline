#!/bin/bash
# Instala (o desinstala) la barra de estado en settings.json de Claude Code.
#   ./install.sh               configura statusLine apuntando a este directorio
#   ./install.sh --uninstall   quita statusLine (solo si apunta a este directorio)
#   ./install.sh --force       sobrescribe un statusLine distinto que ya tengas
# Hace copia de seguridad de settings.json antes de modificarlo.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
CMD="$DIR/statusline.sh"
modo=install; force=0
for a in "$@"; do case "$a" in
  --uninstall) modo=uninstall ;; --force) force=1 ;;
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Opción desconocida: $a" >&2; exit 2 ;; esac; done

if ! diag=$("$DIR/statusline.sh" --doctor 2>&1); then
  printf '%s\n' "$diag" >&2; echo "Faltan dependencias imprescindibles." >&2; exit 1
fi
mkdir -p "$(dirname "$CFG")"
[ -f "$CFG" ] || echo '{}' >"$CFG"
jq -e . "$CFG" >/dev/null 2>&1 || { echo "$CFG no es JSON válido; no lo toco." >&2; exit 1; }
actual=$(jq -r '.statusLine.command // ""' "$CFG")

if [ "$modo" = uninstall ]; then
  [ "$actual" = "$CMD" ] || { echo "El statusLine de $CFG no apunta a este directorio; no hago nada."; exit 0; }
  nuevo=$(jq 'del(.statusLine)' "$CFG")
  msg="Desinstalado."
else
  if [ -n "$actual" ] && [ "$actual" != "$CMD" ] && [ "$force" -ne 1 ]; then
    echo "Ya tienes otro statusLine configurado: $actual" >&2
    echo "Usa --force para reemplazarlo (se guarda copia de seguridad)." >&2; exit 1
  fi
  nuevo=$(jq --arg c "$CMD" '.statusLine = {type:"command", command:$c, refreshInterval:10}' "$CFG")
  msg="Instalado. Reinicia Claude Code para verlo."
fi

cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$nuevo" >"$CFG"
echo "$msg"
echo "  settings: $CFG (copia de seguridad junto al fichero)"
