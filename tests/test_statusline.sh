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
# Output without colour codes and OSC 8 links, to compare plain text
plain() { perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\a]*\a//g'; }
ok()  { printf '  ✔ %s\n' "$1"; }
bad() { printf '  ✖ %s\n' "$1"; failures=$((failures + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Copy of the scripts so diffserver.py can be "updated" without touching the repo
cp -R "$ROOT/statusline.sh" "$ROOT/diffserver.py" "$ROOT/VERSION" "$ROOT/lang" "$TMP/"
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
# Repositories: the bar registers the ones it is used in, and the server serves only those
top_repo=$(git -C "$TMP/repo" rev-parse --show-toplevel)
chk "the bar registers the repository it runs in"      '[ "$(cat "$STATE/repos" 2>/dev/null)" = "$top_repo" ]'
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1
chk "and registers it only once"                       '[ "$(grep -c . "$STATE/repos")" = 1 ]'
perm_r=$(stat -c %a "$STATE/repos" 2>/dev/null || stat -f %Lp "$STATE/repos")
chk "the registry has 600 permissions"                 '[ "$perm_r" = 600 ]'
git init -q "$TMP/unregistered" && echo secret >"$TMP/unregistered/s.txt"
wait_server
chk "the server serves the registered repository"      '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/?t=$(cat "$STATE/token")&d=$top_repo")" = 200 ]'
chk "and refuses one the bar was never used in"        '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/?t=$(cat "$STATE/token")&d=$TMP/unregistered")" = 400 ]'
nl_dir="$TMP/with
newline"; git init -q "$nl_dir"; echo x >"$nl_dir/f.txt"
echo "{\"model\":{\"display_name\":\"M\"},\"workspace\":{\"current_dir\":\"$nl_dir\"}}" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1
chk "a path with a newline is never registered"        '[ "$(grep -c . "$STATE/repos")" = 1 ]'

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

# Billing mode: subscription (Claude Code reports usage limits) vs API (it does not)
LIMITS='"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":9999999999}}'
# shellcheck disable=SC2163  # "$kv" is an assignment like VAR=value on purpose
bill_in() {   # $1 = extra JSON fields (or empty), $2... = VAR=value
  local extra="$1"; shift
  echo "$NO_GIT${extra:+,$extra},\"transcript_path\":\"$TMP/t_old.jsonl\"}" \
    | ( for kv in "$@"; do export "$kv"; done; timeout_run "$TMP/statusline.sh" ) 2>/dev/null
}
api=$(bill_in "" | plain); sub=$(bill_in "$LIMITS" | plain)
chk "api (no usage limits): the cost is plain, with the \$/h rate"   '[[ "$api" == *"\$3.00"* && "$api" == *"\$6/h"* && "$api" != *"≈\$3.00"* ]]'
chk "api: the warning gives the re-cache cost in money"               '[[ "$api" == *"re-caches 200.0k ≈ \$1.25"* ]]'
chk "subscription: the cost is shown as an approximation"             '[[ "$sub" == *"≈\$3.00"* ]]'
chk "subscription: the \$/h rate is hidden"                          '[[ "$sub" != *"/h"* ]]'
chk "subscription: the 5h limit is still drawn"                       '[[ "$sub" == *"5h"* ]]'
chk "subscription: the warning talks about the limit, not money"      '[[ "$sub" == *"uses more of your usage limit"* && "$sub" != *"\$1.25"* ]]'
chk "STATUSLINE_BILLING=api forces api even with usage limits"        '[[ "$(bill_in "$LIMITS" STATUSLINE_BILLING=api | plain)" == *"\$6/h"* ]]'
chk "STATUSLINE_BILLING=subscription forces it without usage limits"  '[[ "$(bill_in "" STATUSLINE_BILLING=subscription | plain)" == *"≈\$3.00"* ]]'
chk "an invalid STATUSLINE_BILLING behaves as auto"                   '[[ "$(bill_in "" STATUSLINE_BILLING=nope | plain)" == *"\$6/h"* && "$(bill_in "$LIMITS" STATUSLINE_BILLING=nope | plain)" == *"≈\$3.00"* ]]'
chk "subscription: the cost is never coloured by dollar thresholds"   '! bill_in "$LIMITS" | grep -q $'"'"'\033\[3[13]m\$3.00'"'"'; ! bill_in "$LIMITS" | grep -q $'"'"'\033\[31m≈'"'"
chk "api: a high cost is still coloured red"                          'echo "$NO_GIT,\"transcript_path\":\"$TMP/t_old.jsonl\"}" | sed "s/\"total_cost_usd\":3.0/\"total_cost_usd\":12.0/" | timeout_run "$TMP/statusline.sh" 2>/dev/null | grep -q $'"'"'\033\[31m\$12.00'"'"
chk "subscription warning is translated (es)"                         '[[ "$(bill_in "$LIMITS" STATUSLINE_LANG=es | plain)" == *"límite de uso"* ]]'
chk "subscription warning is translated (de)"                         '[[ "$(bill_in "$LIMITS" STATUSLINE_LANG=de | plain)" == *"Nutzungslimit"* ]]'

# Exact prompt cache data from Claude Code (prompt_cache.*) wins over the estimate from the transcript
hm_of() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }
# shellcheck disable=SC2163  # "$kv" is an assignment like VAR=value on purpose
pc_in() {   # $1 = prompt_cache JSON object, $2 = transcript file, $3... = VAR=value
  local pc="$1" tr="$2"; shift 2
  echo "$NO_GIT,\"prompt_cache\":$pc,\"transcript_path\":\"$tr\"}" \
    | ( for kv in "$@"; do export "$kv"; done; timeout_run "$TMP/statusline.sh" ) 2>/dev/null | plain
}
now=$(date +%s)
touch "$TMP/t_fresh2.jsonl"
fut=$((now + 600)); pst=$((now - 120)); far=$((now + 3000))
o=$(pc_in "{\"expires_at\":$fut,\"ttl\":\"5m\",\"recache_tokens_if_cold\":90000}" "$TMP/t_old.jsonl")
chk "exact expiry in the future wins over an old transcript"  '[[ "$o" == *"↺$(hm_of $fut)"* && "$o" != *expired* ]]'
o=$(pc_in "{\"expires_at\":$pst,\"ttl\":\"5m\",\"recache_tokens_if_cold\":200000}" "$TMP/t_fresh2.jsonl")
chk "exact expiry in the past wins over a fresh transcript"   '[[ "$o" == *"exp $(hm_of $pst)"* && "$o" == *"expired"* ]]'
chk "the warning uses recache_tokens_if_cold, not the context" '[[ "$o" == *"re-caches 200.0k ≈ \$1.25"* ]]'
o=$(pc_in "{\"expires_at\":$far,\"ttl\":\"1h\"}" "$TMP/t_old.jsonl")
chk "a 1-hour cache is shown with its real expiry"            '[[ "$o" == *"↺$(hm_of $far)"* && "$o" != *expired* ]]'
o=$(pc_in "{\"expires_at\":$pst,\"recache_tokens_if_cold\":30000}" "$TMP/t_fresh2.jsonl")
chk "a cold cache under 50k tokens gives no warning"          '[[ "$o" == *"exp "* && "$o" != *expired* ]]'
o=$(pc_in "{\"caching_observed\":false,\"expires_at\":$pst,\"recache_tokens_if_cold\":200000}" "$TMP/t_old.jsonl")
chk "caching not observed: no countdown and no warning"       '[[ "$o" != *↺* && "$o" != *"exp "* && "$o" != *expired* ]]'
o=$(pc_in "{\"expires_at\":null,\"warm\":false}" "$TMP/t_old.jsonl")
chk "without an expiry it falls back to the transcript"       '[[ "$o" == *expired* ]]'
o=$(pc_in "{\"expires_at\":$pst,\"recache_tokens_if_cold\":200000}" "$TMP/t_fresh2.jsonl" STATUSLINE_BILLING=subscription)
chk "subscription: the exact tokens appear in the limit warning" '[[ "$o" == *"re-caches 200.0k"*"usage limit"* && "$o" != *"\$1.25"* ]]'
o=$(pc_in "{\"expires_at\":$pst,\"recache_tokens_if_cold\":200000}" "$TMP/t_fresh2.jsonl" STATUSLINE_LANG=de)
chk "the exact-data warning is translated"                    '[[ "$o" == *"Cache abgelaufen"*"200.0k"* ]]'
o=$(pc_in "{\"expires_at\":$pst,\"recache_tokens_if_cold\":160000}" "$TMP/t_fresh2.jsonl" 'STATUSLINE_RECACHE_USD_PER_MTOK=10')
chk "STATUSLINE_RECACHE_USD_PER_MTOK still applies"           '[[ "$o" == *"re-caches 160.0k ≈ \$1.60"* ]]'

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

# Languages: STATUSLINE_LANG > $STATE/lang file > English; unknown values fall back to English
unset STATUSLINE_LANG
bar_in() { echo "$JSON" | STATUSLINE_LANG="$1" timeout_run "$TMP/statusline.sh" 2>/dev/null; }
old_in() { echo "$NO_GIT,\"transcript_path\":\"$TMP/t_old.jsonl\"}" | STATUSLINE_LANG="$1" timeout_run "$TMP/statusline.sh" 2>/dev/null; }
chk "lang es: help link is translated"       '[[ "$(bar_in es)" == *"ⓘ ayuda"* ]]'
chk "lang fr: help link is translated"       '[[ "$(bar_in fr)" == *"ⓘ aide"* ]]'
chk "lang de: help link is translated"       '[[ "$(bar_in de)" == *"ⓘ Hilfe"* ]]'
chk "lang pt: help link is translated"       '[[ "$(bar_in pt)" == *"ⓘ ajuda"* ]]'
chk "lang en: help link stays in English"    '[[ "$(bar_in en)" == *"ⓘ help"* ]]'
chk "lang es: expired-cache warning is translated"  '[[ "$(old_in es)" == *"Caché caducada"*"200.0k"*"\$1.25"* ]]'
chk "lang de: expired-cache warning is translated"  '[[ "$(old_in de)" == *"Cache abgelaufen"*"200.0k"*"\$1.25"* ]]'
chk "unknown language falls back to English"        '[[ "$(bar_in zz)" == *"ⓘ help"* ]]'
chk "invalid language value falls back to English"  '[[ "$(bar_in "../x")" == *"ⓘ help"* ]]'
chk "es_ES is accepted as es"                       '[[ "$(bar_in es_ES)" == *"ⓘ ayuda"* ]]'
echo de >"$STATE/lang"
chk "the lang file in the state folder is used"     '[[ "$(echo "$JSON" | timeout_run "$TMP/statusline.sh" 2>/dev/null)" == *"ⓘ Hilfe"* ]]'
chk "STATUSLINE_LANG wins over the lang file"       '[[ "$(bar_in fr)" == *"ⓘ aide"* ]]'
rm -f "$STATE/lang"
chk "a missing key in a language falls back to English" '
  mkdir -p "$TMP/lang_partial" && cp -R "$TMP/lang" "$TMP/lang_partial/lang" && cp "$TMP/statusline.sh" "$TMP/diffserver.py" "$TMP/VERSION" "$TMP/lang_partial/" &&
  jq "del(.bar.help)" "$TMP/lang_partial/lang/es.json" >"$TMP/lang_partial/x" && mv "$TMP/lang_partial/x" "$TMP/lang_partial/lang/es.json" &&
  [[ "$(echo "$JSON" | STATUSLINE_LANG=es timeout_run "$TMP/lang_partial/statusline.sh" 2>/dev/null)" == *"ⓘ help"* ]]'
# Changing the language restarts the server so the help page follows it
pid_before=$(cat "$STATE/server.pid")
bar_in es >/dev/null; sleep 1; wait_server
chk "changing the language restarts the server" '[ "$(cat "$STATE/server.pid")" != "$pid_before" ]'
chk "and the new server answers in that language" '[[ "$(curl -s --max-time 5 "http://127.0.0.1:$STATUSLINE_PORT/help?t=$(cat "$STATE/token")")" == *"barra de estado"* ]]'

# File list modes: STATUSLINE_FILES=full|compact|count|off and STATUSLINE_MAX_FILES=N
git init -q "$TMP/big" && for i in $(seq -w 1 25); do echo x >"$TMP/big/f$i.txt"; done
BIG='{"model":{"display_name":"M"},"workspace":{"current_dir":"'"$TMP/big"'"}}'
# shellcheck disable=SC2163  # "$kv" is an assignment like VAR=value on purpose
files_out() { echo "$BIG" | ( for kv in "$@"; do export "$kv"; done; timeout_run "$TMP/statusline.sh" ) 2>/dev/null | plain; }
d=$(files_out)
chk "default (compact) lists the first 10 files"      '[[ "$d" == *f01.txt* && "$d" == *f10.txt* && "$d" != *f11.txt* ]]'
chk "default (compact) says how many are hidden"      '[[ "$d" == *"+15 more"* ]]'
d=$(files_out STATUSLINE_MAX_FILES=3)
chk "STATUSLINE_MAX_FILES=3 lists 3 and hides 22"     '[[ "$d" == *f03.txt* && "$d" != *f04.txt* && "$d" == *"+22 more"* ]]'
d=$(files_out STATUSLINE_FILES=full)
chk "full lists every file and no 'more'"             '[[ "$d" == *f25.txt* && "$d" != *more* ]]'
d=$(files_out STATUSLINE_FILES=count)
chk "count shows the total and the untracked count"   '[[ "$d" == *"Δ 25 · ?25"* && "$d" != *f01.txt* ]]'
d=$(files_out STATUSLINE_FILES=off)
chk "off hides the list completely"                   '[[ "$d" != *Δ* && "$d" != *f01.txt* ]]'
d=$(files_out STATUSLINE_FILES=bogus)
chk "an invalid mode behaves as compact"              '[[ "$d" == *"+15 more"* ]]'
d=$(files_out STATUSLINE_MAX_FILES=abc)
chk "an invalid max behaves as 10"                    '[[ "$d" == *"+15 more"* ]]'
d=$(files_out STATUSLINE_MAX_FILES=0)
chk "a max of 0 behaves as 10"                        '[[ "$d" == *"+15 more"* ]]'
d=$(files_out STATUSLINE_MAX_FILES=25)
chk "with as many files as the max nothing is hidden" '[[ "$d" == *f25.txt* && "$d" != *more* ]]'
d=$(echo "$JSON" | timeout_run "$TMP/statusline.sh" 2>/dev/null | plain)
chk "few files: the list is unchanged (no 'more')"    '[[ "$d" == *"Δ"* && "$d" != *more* ]]'
d=$(files_out STATUSLINE_LANG=es)
chk "the 'more' text is translated"                   '[[ "$d" == *"+15 más"* ]]'
raw=$(echo "$BIG" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
more_url=$(printf '%s' "$raw" | perl -ne 'print $1 if /\e\]8;;([^\a]*)\a(?:\e\[[0-9;]*m)*\+15 more/')
chk "the 'more' link opens the full page (no anchor)" '[[ "$more_url" == http://127.0.0.1:*"/?t="*"&d="* && "$more_url" != *"#"* ]]'
# Mixed statuses in count mode: M A D ? in this order, each with its number
git init -q "$TMP/mix" && G2=(git -C "$TMP/mix" -c user.email=t@e.c -c user.name=t)
for n in a b c; do echo "$n" >"$TMP/mix/$n.txt"; done; "${G2[@]}" add -A; "${G2[@]}" commit -qm base
echo changed >"$TMP/mix/a.txt"; rm "$TMP/mix/b.txt"; echo new >"$TMP/mix/d.txt"; "${G2[@]}" add d.txt; echo u >"$TMP/mix/e.txt"
MIX='{"model":{"display_name":"M"},"workspace":{"current_dir":"'"$TMP/mix"'"}}'
d=$(echo "$MIX" | STATUSLINE_FILES=count timeout_run "$TMP/statusline.sh" 2>/dev/null | plain)
chk "count breaks the total down by status"           '[[ "$d" == *"Δ 4 · M1 A1 D1 ?1"* ]]'

chk "--version works"  '"$TMP/statusline.sh" --version | grep -q "^claude-code-statusline [0-9]"'
chk "--doctor works"   '"$TMP/statusline.sh" --doctor >/dev/null'

[ "$failures" -eq 0 ] && echo "OK" || { echo "$failures failure(s)"; exit 1; }
