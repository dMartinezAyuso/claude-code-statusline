#!/bin/bash
# shellcheck disable=SC2034  # the variables are used inside the strings that chk() evaluates
# Test of install.sh: language detection and choice, idempotent install, uninstall.
# Uses temporary configuration and state folders, never the real ones.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; failures=0
trap 'rm -rf "$TMP"' EXIT
ok()  { printf '  ✔ %s\n' "$1"; }
bad() { printf '  ✖ %s\n' "$1"; failures=$((failures + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

new_env() {   # fresh config + state folders for each case
  rm -rf "$TMP/cfg" "$TMP/state"; mkdir -p "$TMP/cfg"
  export CLAUDE_CONFIG_DIR="$TMP/cfg" XDG_STATE_HOME="$TMP/state"
  unset STATUSLINE_LANG LC_ALL LC_MESSAGES LANG
}
STATE_LANG() { cat "$TMP/state/claude-code-statusline/lang" 2>/dev/null; }
install_with() { env "$@" "$ROOT/install.sh" 2>&1; }

new_env; out=$(install_with LC_ALL=es_ES.UTF-8)
chk "detects Spanish from LC_ALL"             '[ "$(STATE_LANG)" = es ]'
chk "tells which language it chose"           '[[ "$out" == *"Language: es"* ]]'
new_env; install_with LANG=fr_FR.UTF-8 >/dev/null
chk "detects French from LANG"                '[ "$(STATE_LANG)" = fr ]'
new_env; install_with LANG=pt_BR.UTF-8 >/dev/null
chk "detects Portuguese (pt_BR) as pt"        '[ "$(STATE_LANG)" = pt ]'
new_env; install_with LANG=de_DE.UTF-8 >/dev/null
chk "detects German from LANG"                '[ "$(STATE_LANG)" = de ]'
new_env; install_with LANG=ja_JP.UTF-8 >/dev/null
chk "an unsupported language falls back to en" '[ "$(STATE_LANG)" = en ]'
new_env; install_with LANG=C >/dev/null
chk "the C locale falls back to en"            '[ "$(STATE_LANG)" = en ]'
new_env; install_with LC_ALL=es_ES.UTF-8 LANG=fr_FR.UTF-8 >/dev/null
chk "LC_ALL has priority over LANG"            '[ "$(STATE_LANG)" = es ]'

new_env; out=$(env LANG=es_ES.UTF-8 "$ROOT/install.sh" --lang fr 2>&1)
chk "--lang overrides the detected language"   '[ "$(STATE_LANG)" = fr ]'
new_env; "$ROOT/install.sh" --lang pt_BR >/dev/null 2>&1
chk "--lang accepts pt_BR"                     '[ "$(STATE_LANG)" = pt ]'
new_env; out=$("$ROOT/install.sh" --lang zz 2>&1); code=$?
chk "--lang with an unknown language fails"    '[ "$code" = 2 ] && [[ "$out" == *"Available:"* ]] && [[ "$out" == *" es"* && "$out" == *" fr"* && "$out" == *" pt"* && "$out" == *" de"* ]]'
chk "and it installs nothing"                  '[ ! -f "$TMP/cfg/settings.json" ] && [ -z "$(STATE_LANG)" ]'

new_env; install_with LANG=es_ES.UTF-8 >/dev/null; "$ROOT/install.sh" --lang de >/dev/null 2>&1
chk "--lang changes the language later"        '[ "$(STATE_LANG)" = de ]'
chk "and does not touch settings.json again"   '[ "$(ls "$TMP/cfg" | grep -c "settings.json.bak")" = 1 ]'
install_with LANG=fr_FR.UTF-8 >/dev/null
chk "re-running install keeps the chosen language" '[ "$(STATE_LANG)" = de ]'
out=$("$ROOT/install.sh" 2>&1)
chk "re-running install says it is already installed" '[[ "$out" == *"Already installed"* ]]'
chk "and does not create more backups"         '[ "$(ls "$TMP/cfg" | grep -c "settings.json.bak")" = 1 ]'

new_env; "$ROOT/install.sh" >/dev/null 2>&1; "$ROOT/install.sh" --uninstall >/dev/null 2>&1
chk "uninstall still removes the statusLine"   '[ "$(jq -r ".statusLine // \"none\"" "$TMP/cfg/settings.json")" = none ]'
chk "and keeps the language file"              '[ -n "$(STATE_LANG)" ]'
chk "the state folder is private (700)"        '[ "$(stat -c %a "$TMP/state/claude-code-statusline" 2>/dev/null || stat -f %Lp "$TMP/state/claude-code-statusline")" = 700 ]'

[ "$failures" -eq 0 ] && echo "OK" || { echo "$failures failure(s)"; exit 1; }
