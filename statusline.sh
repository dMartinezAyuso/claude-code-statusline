#!/bin/bash
# Statusline personalizado (3 líneas):
#  1) modelo/esfuerzo · proyecto · rama (ahead/behind) · estado git · PR
#  2) contexto · límites de uso 5h/7d (con cuenta atrás) · coste · caché · tokens · duración · líneas
#  3) todos los ficheros cambiados respecto a HEAD con su estado (envuelto en varias líneas)
export LC_ALL=C

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  --version|-V)
    echo "claude-code-statusline $(cat "$DIR_SCRIPT/VERSION" 2>/dev/null || echo desconocida)"; exit 0 ;;
  --doctor)
    # Comprueba dependencias y estado; sale con 1 si falta algo imprescindible
    fallo=0
    for c in bash jq git nc python3 awk cksum; do
      if command -v "$c" >/dev/null 2>&1; then printf '  ✔ %s\n' "$c"; else printf '  ✖ %s (falta)\n' "$c"; fallo=1; fi
    done
    printf '  versión: %s\n' "$(cat "$DIR_SCRIPT/VERSION" 2>/dev/null || echo desconocida)"
    printf '  estado:  %s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-statusline"
    exit "$fallo" ;;
  -h|--help)
    echo "Uso: statusline.sh [--version|--doctor|--help]   (sin argumentos lee el JSON de Claude Code por stdin)"; exit 0 ;;
esac

input=$(cat)

# Dónde se guarda el estado (token, pid del servidor)
DIR_ESTADO="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-statusline"
PUERTO="${STATUSLINE_PORT:-8765}"
mkdir -p "$DIR_ESTADO" && chmod 700 "$DIR_ESTADO"
# Token aleatorio (solo lectura para ti) que el servidor exige en cada petición
if [ ! -s "$DIR_ESTADO/token" ]; then
  ( umask 077; LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 32 >"$DIR_ESTADO/token" )
fi
TOKEN=$(cat "$DIR_ESTADO/token" 2>/dev/null)

# Arranca el servidor de diffs si no corre; si corre con una versión distinta del código
# (p. ej. tras un `git pull`), lo reinicia para que nunca quede código antiguo en ejecución.
asegura_servidor() {
  local sello; sello=$(cksum <"$DIR_SCRIPT/diffserver.py" 2>/dev/null | cut -d' ' -f1,2)
  if nc -z 127.0.0.1 "$PUERTO" 2>/dev/null; then
    [ "$(cat "$DIR_ESTADO/server.sello" 2>/dev/null)" = "$sello" ] && return
    [ -s "$DIR_ESTADO/server.pid" ] && kill "$(cat "$DIR_ESTADO/server.pid")" 2>/dev/null
    sleep 0.3
  fi
  printf '%s' "$sello" >"$DIR_ESTADO/server.sello"
  (STATUSLINE_PORT="$PUERTO" STATUSLINE_STATE="$DIR_ESTADO" nohup python3 "$DIR_SCRIPT/diffserver.py" >/dev/null 2>&1 &)
}

# Una sola llamada a jq; separador \x1f para conservar los campos vacíos.
IFS=$'\x1f' read -r model effort dir ctx_size cur tin tout cost dur_ms added removed \
  h5 h5_reset d7 d7_reset hit pr_num pr_state vim agent fast < <(
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
    (if .fast_mode then "1" else "" end)
  ] | map(tostring) | join("\u001f")' 2>/dev/null
)

# Colores
R=$'\033[0m'; DIM=$'\033[2m'; BOLD=$'\033[1m'
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
MAG=$'\033[35m'; BLUE=$'\033[34m'
sep="${DIM} │ ${R}"

# 12345 -> 12.3k, 1234567 -> 1.2M
fmt() {
  awk -v n="${1:-0}" 'BEGIN{ if(n>=1000000) printf "%.1fM", n/1000000; else if(n>=1000) printf "%.1fk", n/1000; else printf "%d", n }'
}

# Color según % de uso (verde <50, amarillo <80, rojo)
pct_color() {
  if [ "$1" -ge 80 ]; then printf '%s' "$RED"; elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"; else printf '%s' "$GREEN"; fi
}

# Barra de $2 posiciones para el porcentaje $1
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
  [ "$left" -le 0 ] && { printf 'ya'; return; }
  if [ "$left" -ge 86400 ]; then printf '%dd%dh' $((left / 86400)) $(((left % 86400) / 3600))
  elif [ "$left" -ge 3600 ]; then printf '%dh%02dm' $((left / 3600)) $(((left % 3600) / 60))
  else printf '%dm' $((left / 60)); fi
}

# Ancho del terminal: $COLUMNS, /dev/tty o el tty de algún proceso ascendente (claude); 110 si no hay forma
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

# ---------- Línea 1: modelo, proyecto, git ----------
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
    # Conteos: staged (X != .), modificados en árbol (Y != .), sin seguimiento (?), conflictos (u)
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
    [ -n "$g" ] && l1+="${sep}${g# }" || l1+="${sep}${GREEN}✔ limpio${R}"

    # Servidor local de diffs (127.0.0.1, solo lectura): se arranca solo si no está corriendo
    asegura_servidor
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    enc() { local x="$1"; x="${x//%/%25}"; x="${x// /%20}"; x="${x//#/%23}"; x="${x//\?/%3F}"; x="${x//&/%26}"; printf '%s' "$x"; }
    base="http://127.0.0.1:${PUERTO}/?t=${TOKEN}&d=$(enc "$top")"
    # Línea 3+: todos los ficheros cambiados respecto a HEAD (orden alfabético, estable), envueltos a ~110 columnas
    if [ $((n_s + n_m + n_u + n_c)) -gt 0 ]; then
      width=$(( $(term_width) - 4 )); cur_len=0
      files_line="${DIM}Δ${R} "; cur_len=2
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        st="${line:0:2}"; f="${line:3}"; f="${f##* -> }"; f="${f%\"}"; f="${f#\"}"
        case "$st" in
          "??") mark="${DIM}?${R}" ;;
          U?|?U|AA|DD) mark="${RED}U${R}" ;;   # conflictos: antes que A*/*D*, que los taparían
          *D*) mark="${RED}D${R}" ;;
          A*) mark="${GREEN}A${R}" ;;
          R*) mark="${CYAN}R${R}" ;;
          *) mark="${YELLOW}M${R}" ;;
        esac
        item_len=$(( ${#f} + 4 ))
        if [ "$cur_len" -gt 2 ] && [ $((cur_len + item_len)) -gt "$width" ]; then
          files_line+=$'\n'"  "; cur_len=2
        fi
        files_line+="${mark} "$'\033]8;;'"${base}#$(enc "$f")"$'\a'"${f}"$'\033]8;;\a'"  "; cur_len=$((cur_len + item_len))
      done < <(git -C "$dir" status --porcelain -uall 2>/dev/null)
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
# ⓘ: enlace a la leyenda de la barra (la sirve diffserver.py)
if [ -n "$l1" ]; then
  l1+=" "$'\033]8;;'"http://127.0.0.1:${PUERTO}/ayuda?t=${TOKEN}"$'\a'"${DIM} ⓘ ayuda ${R}"$'\033]8;;\a'
fi

# ---------- Línea 2: consumo ----------
l2=""
add2() { if [ -n "$l2" ]; then l2+="${sep}$1"; else l2="$1"; fi; }

# Contexto
if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
  pct=$(( cur * 100 / ctx_size )); [ "$pct" -gt 100 ] && pct=100
  c=$(pct_color "$pct")
  add2 "${DIM}ctx${R} ${c}$(bar "$pct" 10) ${pct}%${R}${DIM} ($(fmt "$cur")/$(fmt "$ctx_size"))${R}"
fi

# Límites de uso de la suscripción: lo que llevas gastado y cuándo se renueva
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

# Coste
if [ -n "$cost" ]; then
  if awk "BEGIN{exit !($cost >= 5)}"; then c=$RED; elif awk "BEGIN{exit !($cost >= 1)}"; then c=$YELLOW; else c=$GREEN; fi
  add2 "${c}\$$(printf '%.2f' "$cost")${R}"
fi

# Aciertos de caché de prompt (alto = barato)
if [ -n "$hit" ]; then
  hp=$(awk -v h="$hit" 'BEGIN{printf "%.0f", h*100}')
  if [ "$hp" -ge 70 ]; then c=$GREEN; elif [ "$hp" -ge 40 ]; then c=$YELLOW; else c=$RED; fi
  add2 "${DIM}caché${R} ${c}${hp}%${R}"
fi

# Tokens acumulados
if [ -n "$tin" ] || [ -n "$tout" ]; then
  add2 "${DIM}↓${R}$(fmt "$tin") ${DIM}↑${R}$(fmt "$tout")"
fi

# Duración
if [ -n "$dur_ms" ]; then
  s=$(( dur_ms / 1000 ))
  if [ "$s" -ge 3600 ]; then t="$((s/3600))h$(( (s%3600)/60 ))m"
  elif [ "$s" -ge 60 ]; then t="$((s/60))m$((s%60))s"
  else t="${s}s"; fi
  add2 "${DIM}⏱ ${t}${R}"
fi

# Líneas de código de la sesión
if [ -n "$added" ] || [ -n "$removed" ]; then
  add2 "${GREEN}+${added:-0}${R} ${RED}-${removed:-0}${R}"
fi

[ -n "$l1" ] && printf '%s\n' "$l1"
[ -n "$l2" ] && printf '%s\n' "$l2"
[ -n "$files_line" ] && printf '%s\n' "$files_line"
exit 0
