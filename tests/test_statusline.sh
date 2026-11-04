#!/bin/bash
# shellcheck disable=SC2034  # the variables are used inside the strings that chk() evaluates
# Integration test of statusline.sh: it draws, creates the token with safe permissions and
# restarts the server when its code changes. Uses a temporary state and port.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; failures=0
trap 'kill "$(cat "$TMP/state/claude-code-statusline/server.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$TMP"' EXIT

# Runs with a 20 s cap (perl exists on macOS and Linux) so a hang fails instead of blocking CI
timeout_run() { perl -e 'alarm 20; exec @ARGV' -- "$@"; }
# Waits (up to 15 s) for the port to accept connections: slow runners take a while to start Python
wait_server() { local i; for i in $(seq 1 30); do nc -z -w 1 127.0.0.1 "$STATUSLINE_PORT" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1; }
ok()  { printf '  ✔ %s\n' "$1"; }
bad() { printf '  ✖ %s\n' "$1"; failures=$((failures + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Copy of the scripts so diffserver.py can be "updated" without touching the repo
cp "$ROOT/statusline.sh" "$ROOT/diffserver.py" "$ROOT/VERSION" "$TMP/"
git init -q "$TMP/repo" && echo hello >"$TMP/repo/f.txt"

export XDG_STATE_HOME="$TMP/state"
STATUSLINE_PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
export STATUSLINE_PORT
STATE="$XDG_STATE_HOME/claude-code-statusline"
JSON='{"model":{"display_name":"ModeloX"},"workspace":{"current_dir":"'"$TMP/repo"'"}}'

output=$(echo "$JSON" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
chk "draws the model"                  '[[ "$output" == *ModeloX* ]]'
chk "draws the changed file"        '[[ "$output" == *f.txt* ]]'
chk "the link carries the token"         '[[ "$output" == *"t=$(cat "$STATE/token")"* ]]'
chk "32-character token"           '[ "$(wc -c <"$STATE/token" | tr -d " ")" = 32 ]'
perm_f=$(stat -c %a "$STATE/token" 2>/dev/null || stat -f %Lp "$STATE/token")
perm_d=$(stat -c %a "$STATE" 2>/dev/null || stat -f %Lp "$STATE")
chk "token has 600 permissions"           '[ "$perm_f" = 600 ]'
chk "state folder has 700 permissions" '[ "$perm_d" = 700 ]'

wait_server
chk "the server answers 403 without a token" '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/help")" = 403 ]'
chk "the server answers 200 with a token" '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/help?t=$(cat "$STATE/token")")" = 200 ]'

pid1=$(cat "$STATE/server.pid")
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1; sleep 0.5
chk "no changes: the server is not restarted" '[ "$(cat "$STATE/server.pid")" = "$pid1" ]'

echo "# updated" >>"$TMP/diffserver.py"
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1; sleep 1; wait_server
chk "after an update the server restarts" '[ "$(cat "$STATE/server.pid")" != "$pid1" ]'
chk "and the new server answers"         'nc -z -w 1 127.0.0.1 "$STATUSLINE_PORT" >/dev/null 2>&1'

# Merge conflicts: UU and AA (added by both) must be drawn as red U
G=(git -C "$TMP/repo" -c user.email=t@e.c -c user.name=t)
"${G[@]}" add -A; "${G[@]}" commit -qm base
base=$("${G[@]}" symbolic-ref --short HEAD)
"${G[@]}" checkout -qb branchA; echo A >"$TMP/repo/f.txt"; echo A >"$TMP/repo/g.txt"; "${G[@]}" add -A; "${G[@]}" commit -qm A
"${G[@]}" checkout -q "$base"; echo B >"$TMP/repo/f.txt"; echo B >"$TMP/repo/g.txt"; "${G[@]}" add -A; "${G[@]}" commit -qm B
"${G[@]}" merge branchA >/dev/null 2>&1
output=$(echo "$JSON" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
redU=$'\033[31mU\033[0m'
chk "there is a UU or AA conflict in the test repo" '"${G[@]}" status --porcelain | grep -qE "^(UU|AA) "'
chk "conflicts are drawn as red U" '[ "$(grep -oF "$redU" <<<"$output" | wc -l | tr -d " ")" = 2 ]'

# Some launchers (e.g. macOS runners) start processes with SIGPIPE ignored:
# the token must not be generated with pipelines that depend on that signal.
rm -rf "$XDG_STATE_HOME/sigpipe"; mkdir -p "$XDG_STATE_HOME/sigpipe"
chk "with SIGPIPE ignored it finishes (does not hang) and generates the token" 'XDG_STATE_HOME="$XDG_STATE_HOME/sigpipe" perl -e '"'"'$SIG{PIPE}="IGNORE"; alarm 20; exec @ARGV'"'"' -- "$TMP/statusline.sh" >/dev/null 2>&1 <<<"$JSON" && [ "$(wc -c <"$XDG_STATE_HOME/sigpipe/claude-code-statusline/token" | tr -d " ")" = 32 ]'

# Prompt cache (5 min TTL), spend rate and re-cache warning. No repo: line 2 only.
NO_GIT='{"model":{"display_name":"Opus"},"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":200000}},"cost":{"total_cost_usd":3.0,"total_duration_ms":1800000}'
touch "$TMP/t_fresh.jsonl"; touch -t 200001010000 "$TMP/t_old.jsonl"
fresh=$(echo "$NO_GIT,\"transcript_path\":\"$TMP/t_fresh.jsonl\"}" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
old=$(echo "$NO_GIT,\"transcript_path\":\"$TMP/t_old.jsonl\"}" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
none=$(echo "$NO_GIT}" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
chk "live cache: shows the expiry time ↺HH:MM" '[[ "$fresh" =~ ↺[0-9][0-9]:[0-9][0-9] ]]'
chk "live cache: no re-cache warning"                    '[[ "$fresh" != *expired* ]]'
chk "expired cache: warns with context size and cost"  '[[ "$old" == *"expired"*"200.0k"*"\$1.25"* ]]'
chk "no transcript: no countdown and no warning"        '[[ "$none" != *↺* && "$none" != *expired* ]]'
chk "spend rate: \$3 in 30 min = \$6/h"              '[[ "$fresh" == *"\$6/h"* ]]'
# $/h colour thresholds are configurable: grey below the first, yellow from it, red from the second
burn_color() {   # $1 = warn threshold, $2 = high threshold (either may be empty for the default)
  echo "$NO_GIT}" | STATUSLINE_BURN_WARN="$1" STATUSLINE_BURN_HIGH="$2" timeout_run "$TMP/statusline.sh" 2>/dev/null \
    | grep -o $'\033\\[[0-9]*m\\$6/h' | head -1
}
chk "burn: default thresholds keep \$6/h grey"          '[ "$(burn_color "" "")" = $'"'"'\033[2m$6/h'"'"' ]'
chk "burn: STATUSLINE_BURN_WARN=5 turns \$6/h yellow"   '[ "$(burn_color 5 "")" = $'"'"'\033[33m$6/h'"'"' ]'
chk "burn: STATUSLINE_BURN_HIGH=5 turns \$6/h red"      '[ "$(burn_color "" 5)" = $'"'"'\033[31m$6/h'"'"' ]'
chk "burn: invalid values fall back to the defaults"     '[ "$(burn_color abc -1)" = $'"'"'\033[2m$6/h'"'"' ]'

# Re-cache price by model: 5-minute cache-write price from https://platform.claude.com/docs/en/about-claude/pricing
recache_cost() {   # $1 = model display name, $2 = context tokens
  echo "{\"model\":{\"display_name\":\"$1\"},\"context_window\":{\"context_window_size\":1000000,\"current_usage\":{\"input_tokens\":$2}},\"transcript_path\":\"$TMP/t_old.jsonl\"}" \
    | timeout_run "$TMP/statusline.sh" 2>/dev/null | grep -o 're-caches [^ ]* ≈ \$[0-9.]*' | sed 's/.*≈ //'
}
chk "price: Opus 5.5 = \$5 per MTok"        '[ "$(recache_cost "Opus 5.5" 200000)" = "\$1.00" ]'
chk "price: Opus 5 = \$6.25 per MTok"       '[ "$(recache_cost "Opus 5" 200000)" = "\$1.25" ]'
chk "price: Sonnet 5.5 = \$2.50 per MTok"   '[ "$(recache_cost "Sonnet 5.5" 200000)" = "\$0.50" ]'
chk "price: Sonnet 4.6 = \$3.75 per MTok"   '[ "$(recache_cost "Sonnet 4.6" 200000)" = "\$0.75" ]'
chk "price: Haiku 4.5 = \$1.25 per MTok"    '[ "$(recache_cost "Haiku 4.5" 200000)" = "\$0.25" ]'
chk "price: Haiku 5.5 up to 100k = \$0.125" '[ "$(recache_cost "Haiku 5.5" 80000)" = "\$0.01" ]'
chk "price: Haiku 5.5 over 100k = \$0.625"  '[ "$(recache_cost "Haiku 5.5" 160000)" = "\$0.10" ]'
chk "price: Fable 5.1 = \$12.50 per MTok"   '[ "$(recache_cost "Fable 5.1" 200000)" = "\$2.50" ]'
chk "STATUSLINE_RECACHE_USD_PER_MTOK changes the cost"   '[[ "$(echo "$NO_GIT,\"transcript_path\":\"$TMP/t_old.jsonl\"}" | STATUSLINE_RECACHE_USD_PER_MTOK=10 timeout_run "$TMP/statusline.sh" 2>/dev/null)" == *"\$2.00"* ]]'

chk "--version works"  '"$TMP/statusline.sh" --version | grep -q "^claude-code-statusline [0-9]"'
chk "--doctor works"   '"$TMP/statusline.sh" --doctor >/dev/null'

[ "$failures" -eq 0 ] && echo "OK" || { echo "$failures failure(s)"; exit 1; }
