#!/bin/bash
# Installs (or uninstalls) the status bar in Claude Code's settings.json.
#   ./install.sh               sets statusLine pointing to this directory
#   ./install.sh --uninstall   removes statusLine (only if it points to this directory)
#   ./install.sh --force       overwrites a different statusLine you already have
# Backs up settings.json before modifying it.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
CMD="$DIR/statusline.sh"
mode=install; force=0
for a in "$@"; do case "$a" in
  --uninstall) mode=uninstall ;; --force) force=1 ;;
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $a" >&2; exit 2 ;; esac; done

if ! diag=$("$DIR/statusline.sh" --doctor 2>&1); then
  printf '%s\n' "$diag" >&2; echo "Essential dependencies are missing." >&2; exit 1
fi
mkdir -p "$(dirname "$CFG")"
[ -f "$CFG" ] || echo '{}' >"$CFG"
jq -e . "$CFG" >/dev/null 2>&1 || { echo "$CFG is not valid JSON; leaving it alone." >&2; exit 1; }
current=$(jq -r '.statusLine.command // ""' "$CFG")

if [ "$mode" = uninstall ]; then
  [ "$current" = "$CMD" ] || { echo "The statusLine in $CFG does not point to this directory; doing nothing."; exit 0; }
  new_cfg=$(jq 'del(.statusLine)' "$CFG")
  msg="Uninstalled."
else
  if [ -n "$current" ] && [ "$current" != "$CMD" ] && [ "$force" -ne 1 ]; then
    echo "You already have another statusLine configured: $current" >&2
    echo "Use --force to replace it (a backup is kept)." >&2; exit 1
  fi
  new_cfg=$(jq --arg c "$CMD" '.statusLine = {type:"command", command:$c, refreshInterval:10}' "$CFG")
  msg="Installed. Restart Claude Code to see it."
fi

cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$new_cfg" >"$CFG"
echo "$msg"
echo "  settings: $CFG (backup next to the file)"
