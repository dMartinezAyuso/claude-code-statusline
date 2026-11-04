#!/bin/bash
# Custom statusline (3 lines):
#  1) model/effort · project · branch (ahead/behind) · git state · PR
#  2) context · 5h/7d usage limits (with countdown) · cost · cache · tokens · duration · lines
#  3) every file changed against HEAD with its status (wrapped over several lines)
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  --version|-V)
    echo "claude-code-statusline $(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
  --doctor)
    # Checks dependencies and state; exits with 1 if something essential is missing
    fallo=0
    for c in bash jq git nc python3 awk cksum; do
      if command -v "$c" >/dev/null 2>&1; then printf '  ✔ %s\n' "$c"; else printf '  ✖ %s (missing)\n' "$c"; fallo=1; fi
    done
    printf '  version: %s\n' "$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
    printf '  state:   %s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-statusline"
    exit "$fallo" ;;
  -h|--help)
    echo "Usage: statusline.sh [--version|--doctor|--help]   (without arguments it reads the Claude Code JSON from stdin)"; exit 0 ;;
esac

input=$(cat)

# Where the state is kept (token, server pid)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-statusline"
PORT="${STATUSLINE_PORT:-8765}"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
# Random token (readable only by you) that the server requires on every request
if [ ! -s "$STATE_DIR/token" ]; then
  # od reads exactly 16 bytes and ends: no endless pipelines (tr -dc over /dev/urandom hangs if SIGPIPE is ignored)
  ( umask 077; od -An -N16 -tx1 /dev/urandom | tr -d ' \n' >"$STATE_DIR/token" )
fi
TOKEN=$(cat "$STATE_DIR/token" 2>/dev/null)

# Language: STATUSLINE_LANG, then the `lang` file of the state folder, then English.
# Only the code of an existing lang/*.json file is accepted; "es_ES" counts as "es".
resolve_lang() {
  local code="${STATUSLINE_LANG:-}"
  [ -z "$code" ] && code=$(cat "$STATE_DIR/lang" 2>/dev/null)
  code=$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]'); code=${code:0:2}
  if [[ "$code" =~ ^[a-z][a-z]$ ]] && [ -f "$SCRIPT_DIR/lang/$code.json" ]; then printf '%s' "$code"; else printf 'en'; fi
}
LANG_CODE=$(resolve_lang)

# Starts the diff server if it is not running; if it runs a different version of the code
# (e.g. after a `git pull`), restarts it so old code is never left running.
ensure_server() {
  # The stamp covers the server code, the language files and the chosen language
  local stamp; stamp=$({ cat "$SCRIPT_DIR/diffserver.py" "$SCRIPT_DIR"/lang/*.json 2>/dev/null; printf '%s' "$LANG_CODE"; } | cksum | cut -d' ' -f1,2)
  if nc -z -w 1 127.0.0.1 "$PORT" 2>/dev/null; then
    [ "$(cat "$STATE_DIR/server.stamp" 2>/dev/null)" = "$stamp" ] && return
    [ -s "$STATE_DIR/server.pid" ] && kill "$(cat "$STATE_DIR/server.pid")" 2>/dev/null
    sleep 0.3
  fi
  printf '%s' "$stamp" >"$STATE_DIR/server.stamp"
  (STATUSLINE_PORT="$PORT" STATUSLINE_STATE="$STATE_DIR" STATUSLINE_LANG="$LANG_CODE" nohup python3 "$SCRIPT_DIR/diffserver.py" >/dev/null 2>&1 &)
}

# A single jq call; \x1f separator to keep empty fields.
IFS=$'\x1f' read -r model effort dir ctx_size cur tin tout cost dur_ms added removed \
  h5 h5_reset d7 d7_reset hit pr_num pr_state vim agent fast transcript < <(
  echo "$input" | jq -r '[
    (.model.display_name // ""),
    (.effort.level // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.context_window_size // ""),
    ((.context_window.current_usage // {}) | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))),
    (.context_window.total_input_tokens // ""),
    (.context_window.total_output_tokens // ""),
    (.cost.total_cost_usd // ""),
    (.cost.total_duration_ms // ""),
    (.cost.total_lines_added // ""),
    (.cost.total_lines_removed // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.prompt_cache.hit_ratio // ""),
    (.pr.number // ""),
    (.pr.review_state // ""),
    (.vim.mode // ""),
    (.agent.name // ""),
    (if .fast_mode then "1" else "" end),
    (.transcript_path // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null
)

# Texts of the chosen language, one jq call; a missing key (or a broken file) falls back to English
L_CACHE=cache; L_CLEAN="✔ clean"; L_HELP="ⓘ help"; L_NOW=now; L_EXP=exp
L_WARN="Cache expired: the next prompt re-caches {tokens} ≈ {cost} → /compact"; L_MORE="+{n} more"
IFS=$'\x1f' read -r t_cache t_clean t_help t_now t_exp t_warn t_more < <(
  jq -rn --slurpfile en "$SCRIPT_DIR/lang/en.json" --slurpfile lg "$SCRIPT_DIR/lang/$LANG_CODE.json" \
    '[ "cache", "clean", "help", "now", "exp", "warn", "more" ] | map(. as $k | ($lg[0].bar[$k] // $en[0].bar[$k] // "")) | join("\u001f")' 2>/dev/null
)
L_CACHE=${t_cache:-$L_CACHE}; L_CLEAN=${t_clean:-$L_CLEAN}; L_HELP=${t_help:-$L_HELP}
L_NOW=${t_now:-$L_NOW}; L_EXP=${t_exp:-$L_EXP}; L_WARN=${t_warn:-$L_WARN}; L_MORE=${t_more:-$L_MORE}

# Colors
R=$'\033[0m'; DIM=$'\033[2m'; BOLD=$'\033[1m'
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
MAG=$'\033[35m'; BLUE=$'\033[34m'
sep="${DIM} │ ${R}"

# 12345 -> 12.3k, 1234567 -> 1.2M
fmt() {
  awk -v n="${1:-0}" 'BEGIN{ if(n>=1000000) printf "%.1fM", n/1000000; else if(n>=1000) printf "%.1fk", n/1000; else printf "%d", n }'
}

# Color by usage % (green <50, yellow <80, red)
pct_color() {
  if [ "$1" -ge 80 ]; then printf '%s' "$RED"; elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"; else printf '%s' "$GREEN"; fi
}

# $2-position bar for the percentage $1
bar() {
  local pct=$1 width=${2:-10} filled i out=""
  filled=$(( pct * width / 100 ))
  for ((i = 1; i <= width; i++)); do
    if [ "$i" -le "$filled" ]; then out+="█"; else out+="░"; fi
  done
  printf '%s' "$out"
}

# Segundos hasta un epoch -> "2h13m" / "3d4h" / "12m"
countdown() {
  local left=$(( $1 - $(date +%s) ))
  [ "$left" -le 0 ] && { printf '%s' "$L_NOW"; return; }
  if [ "$left" -ge 86400 ]; then printf '%dd%dh' $((left / 86400)) $(((left % 86400) / 3600))
  elif [ "$left" -ge 3600 ]; then printf '%dh%02dm' $((left / 3600)) $(((left % 3600) / 60))
  else printf '%dm' $((left / 60)); fi
}

# Terminal width: $COLUMNS, /dev/tty or the tty of some ancestor process (claude); 110 if there is no way
term_width() {
  local w="" pid=$$ t i src=""
  [ "${COLUMNS:-0}" -gt 20 ] 2>/dev/null && { w=$COLUMNS; src=COLUMNS; }
  if [ -z "$w" ]; then
    w=$({ stty size </dev/tty; } 2>/dev/null | awk '{print $2}'); [ -n "$w" ] && src=/dev/tty
  fi
  if [ -z "$w" ]; then
    for i in 1 2 3 4 5 6; do
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' '); [ -z "$pid" ] || [ "$pid" = 1 ] && break
      t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$t" ] && [ "$t" != "??" ]; then
        w=$(stty -f "/dev/$t" size 2>/dev/null | awk '{print $2}'); [ -n "$w" ] && { src="tty $t (pid $pid)"; break; }
      fi
    done
  fi
  [ -z "$w" ] || [ "$w" -lt 40 ] 2>/dev/null && { w=110; src="${src:-defecto}"; }
    echo "$w"
}

# How the changed-file list is shown: full | compact (default) | count | off, and how many files compact lists
files_mode="${STATUSLINE_FILES:-compact}"
case "$files_mode" in full|compact|count|off) ;; *) files_mode=compact ;; esac
max_files="${STATUSLINE_MAX_FILES:-10}"; [[ "$max_files" =~ ^[1-9][0-9]*$ ]] || max_files=10

# ---------- Line 1: model, project, git ----------
l1=""
if [ -n "$model" ]; then
  l1+="${MAG}${BOLD}${model}${R}"
  [ -n "$effort" ] && l1+="${DIM} (${effort})${R}"
  [ -n "$fast" ] && l1+=" ${YELLOW}⚡${R}"
fi
[ -n "$agent" ] && l1+="${sep}${CYAN}🤖 ${agent}${R}"

files_line=""
if [ -n "$dir" ]; then
  l1+="${sep}${BLUE}${dir##*/}${R}"
  if gs=$(git -C "$dir" status --porcelain=v2 --branch 2>/dev/null); then
    branch=$(echo "$gs" | awk '/^# branch.head/{print $3}')
    ab=$(echo "$gs" | awk '/^# branch.ab/{print $3" "$4}')
    l1+=" ${CYAN}⎇ ${branch}${R}"
    if [ -n "$ab" ]; then
      ahead=${ab%% *}; behind=${ab##* }
      [ "${ahead#+}" != "0" ] && l1+=" ${GREEN}↑${ahead#+}${R}"
      [ "${behind#-}" != "0" ] && l1+=" ${RED}↓${behind#-}${R}"
    fi
    # Counts: staged (X != .), modified in the tree (Y != .), untracked (?), conflicts (u)
    counts=$(echo "$gs" | awk '
      /^[12] /{ if (substr($2,1,1)!=".") s++; if (substr($2,2,1)!=".") m++ }
      /^\?/{ u++ }
      /^u /{ c++ }
      END{ printf "%d %d %d %d", s, m, u, c }')
    read -r n_s n_m n_u n_c <<<"$counts"
    g=""
    [ "$n_s" -gt 0 ] && g+=" ${GREEN}●${n_s}${R}"
    [ "$n_m" -gt 0 ] && g+=" ${YELLOW}✚${n_m}${R}"
    [ "$n_u" -gt 0 ] && g+=" ${DIM}?${n_u}${R}"
    [ "$n_c" -gt 0 ] && g+=" ${RED}✖${n_c}${R}"
    [ -n "$g" ] && l1+="${sep}${g# }" || l1+="${sep}${GREEN}${L_CLEAN}${R}"

    # Local diff server (127.0.0.1, read-only): started on its own if it is not running
    ensure_server
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    # Register the repository: the server serves only repositories listed here (one per line, private file)
    if [ -n "$top" ] && [[ "$top" != *$'\n'* ]] && ! grep -qxF -- "$top" "$STATE_DIR/repos" 2>/dev/null; then
      ( umask 077; printf '%s\n' "$top" >>"$STATE_DIR/repos" )
    fi
    enc() { local x="$1"; x="${x//%/%25}"; x="${x// /%20}"; x="${x//#/%23}"; x="${x//\?/%3F}"; x="${x//&/%26}"; printf '%s' "$x"; }
    base="http://127.0.0.1:${PORT}/?t=${TOKEN}&d=$(enc "$top")"
    # Line 3+: every file changed against HEAD (alphabetical, stable order), wrapped at ~110 columns
    if [ $((n_s + n_m + n_u + n_c)) -gt 0 ] && [ "$files_mode" != off ]; then
      width=$(( $(term_width) - 4 )); cur_len=0
      files_line="${DIM}Δ${R} "; cur_len=2
      total=0; listed=0; cnt_M=0; cnt_A=0; cnt_D=0; cnt_R=0; cnt_U=0; cnt_Q=0
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        st="${line:0:2}"; f="${line:3}"; f="${f##* -> }"; f="${f%\"}"; f="${f#\"}"
        case "$st" in
          "??") mark="${DIM}?${R}"; cnt_Q=$((cnt_Q + 1)) ;;
          U?|?U|AA|DD) mark="${RED}U${R}"; cnt_U=$((cnt_U + 1)) ;;   # conflicts: before A*/*D*, which would hide them
          *D*) mark="${RED}D${R}"; cnt_D=$((cnt_D + 1)) ;;
          A*) mark="${GREEN}A${R}"; cnt_A=$((cnt_A + 1)) ;;
          R*) mark="${CYAN}R${R}"; cnt_R=$((cnt_R + 1)) ;;
          *) mark="${YELLOW}M${R}"; cnt_M=$((cnt_M + 1)) ;;
        esac
        total=$((total + 1))
        # compact lists only the first max_files; count lists none; full lists all
        case "$files_mode" in
          count) continue ;;
          compact) [ "$listed" -ge "$max_files" ] && continue ;;
        esac
        listed=$((listed + 1))
        item_len=$(( ${#f} + 4 ))
        if [ "$cur_len" -gt 2 ] && [ $((cur_len + item_len)) -gt "$width" ]; then
          files_line+=$'\n'"  "; cur_len=2
        fi
        files_line+="${mark} "$'\033]8;;'"${base}#$(enc "$f")"$'\a'"${f}"$'\033]8;;\a'"  "; cur_len=$((cur_len + item_len))
      done < <(git -C "$dir" status --porcelain -uall 2>/dev/null)
      if [ "$files_mode" = count ]; then
        # One line: the total and how many files per status, all of it a link to the full page
        files_line="${DIM}Δ${R} ${total} ${DIM}·${R}"
        [ "$cnt_M" -gt 0 ] && files_line+=" ${YELLOW}M${cnt_M}${R}"
        [ "$cnt_A" -gt 0 ] && files_line+=" ${GREEN}A${cnt_A}${R}"
        [ "$cnt_D" -gt 0 ] && files_line+=" ${RED}D${cnt_D}${R}"
        [ "$cnt_R" -gt 0 ] && files_line+=" ${CYAN}R${cnt_R}${R}"
        [ "$cnt_U" -gt 0 ] && files_line+=" ${RED}U${cnt_U}${R}"
        [ "$cnt_Q" -gt 0 ] && files_line+=" ${DIM}?${cnt_Q}${R}"
        files_line=$'\033]8;;'"${base}"$'\a'"${files_line}"$'\033]8;;\a'
      elif [ "$total" -gt "$listed" ]; then
        # Hidden files: a link that opens the page with all of them
        more_tag='{n}'
        files_line+=$'\033]8;;'"${base}"$'\a'"${DIM}${L_MORE//$more_tag/$((total - listed))}${R}"$'\033]8;;\a'
      fi
    fi
  fi
fi
if [ -n "$pr_num" ]; then
  case "$pr_state" in
    approved) pc=$GREEN ;; changes_requested) pc=$RED ;; *) pc=$YELLOW ;;
  esac
  l1+="${sep}${pc}PR #${pr_num}${R}"
fi
[ -n "$vim" ] && l1+="${sep}${DIM}${vim}${R}"
# ⓘ: link to the bar legend (served by diffserver.py)
if [ -n "$l1" ]; then
  l1+=" "$'\033]8;;'"http://127.0.0.1:${PORT}/help?t=${TOKEN}"$'\a'"${DIM} ${L_HELP} ${R}"$'\033]8;;\a'
fi

# ---------- Line 2: usage ----------
l2=""
add2() { if [ -n "$l2" ]; then l2+="${sep}$1"; else l2="$1"; fi; }

# Context
if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
  pct=$(( cur * 100 / ctx_size )); [ "$pct" -gt 100 ] && pct=100
  c=$(pct_color "$pct")
  add2 "${DIM}ctx${R} ${c}$(bar "$pct" 10) ${pct}%${R}${DIM} ($(fmt "$cur")/$(fmt "$ctx_size"))${R}"
fi

# Subscription usage limits: how much you have used and when it renews
if [ -n "$h5" ]; then
  p=$(printf '%.0f' "$h5"); c=$(pct_color "$p")
  s="${DIM}5h${R} ${c}$(bar "$p" 8) ${p}%${R}"
  [ -n "$h5_reset" ] && s+="${DIM} ↻$(countdown "$h5_reset")${R}"
  add2 "$s"
fi
if [ -n "$d7" ]; then
  p=$(printf '%.0f' "$d7"); c=$(pct_color "$p")
  s="${DIM}7d${R} ${c}$(bar "$p" 8) ${p}%${R}"
  [ -n "$d7_reset" ] && s+="${DIM} ↻$(countdown "$d7_reset")${R}"
  add2 "$s"
fi

# Cost
if [ -n "$cost" ]; then
  if awk "BEGIN{exit !($cost >= 5)}"; then c=$RED; elif awk "BEGIN{exit !($cost >= 1)}"; then c=$YELLOW; else c=$GREEN; fi
  burn=""
  # Spend rate ($/h): only after 5 min of session, earlier it is just noise
  if [ -n "$dur_ms" ] && [ "$dur_ms" -ge 300000 ] 2>/dev/null; then
    # Colour thresholds in USD/hour (grey below warn, yellow from warn, red from high); invalid values use the defaults
    burn_warn="${STATUSLINE_BURN_WARN:-15}"; [[ "$burn_warn" =~ ^[0-9]+(\.[0-9]+)?$ ]] || burn_warn=15
    burn_high="${STATUSLINE_BURN_HIGH:-30}"; [[ "$burn_high" =~ ^[0-9]+(\.[0-9]+)?$ ]] || burn_high=30
    read -r rate level < <(awk -v c="$cost" -v d="$dur_ms" -v w="$burn_warn" -v h="$burn_high" \
      'BEGIN{r = c / d * 3600000; printf "%.0f %d", r, (r >= h) ? 2 : ((r >= w) ? 1 : 0)}')
    case "$level" in 2) bc=$RED ;; 1) bc=$YELLOW ;; *) bc=$DIM ;; esac
    burn=" ${bc}\$${rate}/h${R}"
  fi
  add2 "${c}\$$(printf '%.2f' "$cost")${R}${burn}"
fi

# Prompt cache hits (high = cheap)
if [ -n "$hit" ]; then
  hp=$(awk -v h="$hit" 'BEGIN{printf "%.0f", h*100}')
  if [ "$hp" -ge 70 ]; then c=$GREEN; elif [ "$hp" -ge 40 ]; then c=$YELLOW; else c=$RED; fi
  cache_seg="${DIM}${L_CACHE}${R} ${c}${hp}%${R}"
fi

# Prompt cache expiry (5 min after the last activity, approximated with the transcript mtime).
# Once expired, a large context is fully re-cached on the next prompt: warn about it.
CACHE_TTL=300
warning=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # GNU stat first: on Linux `stat -f` means "filesystem status" and prints garbage instead of failing
  mt=$(stat -c %Y "$transcript" 2>/dev/null || stat -f %m "$transcript" 2>/dev/null)
  if [[ "$mt" =~ ^[0-9]+$ ]]; then
    left=$(( mt + CACHE_TTL - $(date +%s) ))
    hm=$(date -r $(( mt + CACHE_TTL )) +%H:%M 2>/dev/null || date -d "@$(( mt + CACHE_TTL ))" +%H:%M 2>/dev/null)
    if [ "$left" -gt 60 ]; then ttl="${GREEN}↺${hm}${R}"
    elif [ "$left" -gt 0 ]; then ttl="${YELLOW}↺${hm}${R}"
    else
      ttl="${RED}${L_EXP} ${hm}${R}"
      # 5-minute cache-write price per million tokens, from the official pricing table
      # (https://platform.claude.com/docs/en/about-claude/pricing). STATUSLINE_RECACHE_USD_PER_MTOK overrides it.
      m=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
      if   [[ "$m" == *fable* || "$m" == *mythos* ]]; then price=12.50
      elif [[ "$m" =~ opus[^0-9]*5\.5 ]]; then price=5.00
      elif [[ "$m" == *opus* ]]; then price=6.25
      elif [[ "$m" =~ sonnet[^0-9]*5 ]]; then price=2.50     # Sonnet 5 and 5.5 (not 4.x)
      elif [[ "$m" == *sonnet* ]]; then price=3.75
      elif [[ "$m" =~ haiku[^0-9]*5 ]]; then                  # Haiku 5.5 is cheaper up to 100k-token prompts
        if [ "${cur:-0}" -le 100000 ] 2>/dev/null; then price=0.125; else price=0.625; fi
      elif [[ "$m" == *haiku* ]]; then price=1.25
      else price=6.25; fi
      price="${STATUSLINE_RECACHE_USD_PER_MTOK:-$price}"
      if [ "${cur:-0}" -ge 50000 ] 2>/dev/null; then
        tok_tag='{tokens}'; cost_tag='{cost}'
        warning="${L_WARN//$tok_tag/$(fmt "$cur")}"
        warning="${RED}${BOLD}${warning//$cost_tag/\$$(awk -v t="$cur" -v r="$price" 'BEGIN{printf "%.2f", t * r / 1000000}')}${R}"
      fi
    fi
    cache_seg="${cache_seg:-${DIM}${L_CACHE}${R}} ${ttl}"
  fi
fi
[ -n "$cache_seg" ] && add2 "$cache_seg"

# Accumulated tokens
if [ -n "$tin" ] || [ -n "$tout" ]; then
  add2 "${DIM}↓${R}$(fmt "$tin") ${DIM}↑${R}$(fmt "$tout")"
fi

# Duration
if [ -n "$dur_ms" ]; then
  s=$(( dur_ms / 1000 ))
  if [ "$s" -ge 3600 ]; then t="$((s/3600))h$(( (s%3600)/60 ))m"
  elif [ "$s" -ge 60 ]; then t="$((s/60))m$((s%60))s"
  else t="${s}s"; fi
  add2 "${DIM}⏱ ${t}${R}"
fi

# Lines of code in the session
if [ -n "$added" ] || [ -n "$removed" ]; then
  add2 "${GREEN}+${added:-0}${R} ${RED}-${removed:-0}${R}"
fi

[ -n "$l1" ] && printf '%s\n' "$l1"
[ -n "$l2" ] && printf '%s\n' "$l2"
[ -n "$warning" ] && printf '%s\n' "$warning"
[ -n "$files_line" ] && printf '%s\n' "$files_line"
exit 0
