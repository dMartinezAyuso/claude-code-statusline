#!/bin/bash
# Installs (or uninstalls) the status bar in Claude Code's settings.json.
#   ./install.sh               sets statusLine pointing to this directory and picks your language
#   ./install.sh --uninstall   removes statusLine (only if it points to this directory)
#   ./install.sh --force       overwrites a different statusLine you already have
#   ./install.sh --lang fr     sets the language of the bar and its help page (en, es, fr, pt, de)
# Backs up settings.json before modifying it. Without --lang, the language is detected from your
# locale (LC_ALL, LC_MESSAGES, LANG, or the macOS system language) the first time and then kept.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
CMD="$DIR/statusline.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-statusline"
mode=install; force=0; lang_arg=""

# Languages available = the lang/*.json files (English first)
available() {
  local f c out="en"
  for f in "$DIR"/lang/*.json; do c=$(basename "$f" .json); [ "$c" = en ] || out+=" $c"; done
  printf '%s' "$out"
}
# "es_ES.UTF-8" / "pt-BR" / "FR" -> "es" / "pt" / "fr" if available, empty otherwise
normalize() {
  local c; c=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'); c=${c:0:2}
  [[ "$c" =~ ^[a-z][a-z]$ ]] && [ -f "$DIR/lang/$c.json" ] && printf '%s' "$c"
  return 0
}
# First locale variable that is set decides; the C/POSIX locale means no preference (English).
# Only when none is set, ask macOS for its system language.
detect_lang() {
  local v found=""
  for v in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
    [ -n "$v" ] && { found="$v"; break; }
  done
  if [ -z "$found" ] && command -v defaults >/dev/null 2>&1; then
    found=$(defaults read -g AppleLanguages 2>/dev/null | sed -n 's/^ *"\{0,1\}\([A-Za-z][A-Za-z]\).*/\1/p' | head -1)
  fi
  case "$found" in C|POSIX|C.*|"") printf 'en'; return ;; esac
  v=$(normalize "$found"); printf '%s' "${v:-en}"
}

while [ $# -gt 0 ]; do case "$1" in
  --uninstall) mode=uninstall ;; --force) force=1 ;;
  --lang) [ $# -ge 2 ] || { echo "--lang needs a language code. Available: $(available)" >&2; exit 2; }
          lang_arg="$2"; shift ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;; esac; shift; done

if [ -n "$lang_arg" ]; then
  lang_arg=$(normalize "$lang_arg")
  [ -n "$lang_arg" ] || { echo "Unknown language. Available: $(available)" >&2; exit 2; }
fi

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
  cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
  printf '%s\n' "$new_cfg" >"$CFG"
  echo "Uninstalled."
  echo "  settings: $CFG (backup next to the file)"
  exit 0
fi

# Language: --lang, else the one already saved, else detected from the locale
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
if [ -n "$lang_arg" ]; then lang="$lang_arg"
elif [ -s "$STATE_DIR/lang" ] && [ -n "$(normalize "$(cat "$STATE_DIR/lang")")" ]; then lang=$(normalize "$(cat "$STATE_DIR/lang")")
else lang=$(detect_lang); fi
printf '%s\n' "$lang" >"$STATE_DIR/lang"

if [ -n "$current" ] && [ "$current" != "$CMD" ] && [ "$force" -ne 1 ]; then
  echo "You already have another statusLine configured: $current" >&2
  echo "Use --force to replace it (a backup is kept)." >&2; exit 1
fi
if [ "$current" = "$CMD" ]; then
  echo "Already installed."
else
  new_cfg=$(jq --arg c "$CMD" '.statusLine = {type:"command", command:$c, refreshInterval:10}' "$CFG")
  cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
  printf '%s\n' "$new_cfg" >"$CFG"
  echo "Installed. Restart Claude Code to see it."
  echo "  settings: $CFG (backup next to the file)"
fi
echo "  Language: $lang (change it with ./install.sh --lang <code>; available: $(available))"
