#!/bin/bash
# shellcheck disable=SC2034  # las variables se usan dentro de las cadenas que evalúa chk()
# Prueba de integración de statusline.sh: pinta, crea el token con permisos seguros y
# reinicia el servidor cuando cambia su código. Usa un estado y un puerto temporales.
set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; fallos=0
trap 'kill "$(cat "$TMP/state/claude-code-statusline/server.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$TMP"' EXIT

# Ejecuta con tope de 20 s (perl existe en macOS y Linux) para que un cuelgue falle en vez de bloquear la CI
timeout_run() { perl -e 'alarm 20; exec @ARGV' -- "$@"; }
# Espera (hasta 15 s) a que el puerto acepte conexiones: los runners lentos tardan en arrancar Python
espera_servidor() { local i; for i in $(seq 1 30); do nc -z -w 1 127.0.0.1 "$STATUSLINE_PORT" >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1; }
ok()  { printf '  ✔ %s\n' "$1"; }
mal() { printf '  ✖ %s\n' "$1"; fallos=$((fallos + 1)); }
chk() { if eval "$2"; then ok "$1"; else mal "$1"; fi; }

# Copia de los scripts para poder "actualizar" diffserver.py sin tocar el repo
cp "$RAIZ/statusline.sh" "$RAIZ/diffserver.py" "$RAIZ/VERSION" "$TMP/"
git init -q "$TMP/repo" && echo hola >"$TMP/repo/f.txt"

export XDG_STATE_HOME="$TMP/state"
STATUSLINE_PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
export STATUSLINE_PORT
ESTADO="$XDG_STATE_HOME/claude-code-statusline"
JSON='{"model":{"display_name":"ModeloX"},"workspace":{"current_dir":"'"$TMP/repo"'"}}'

salida=$(echo "$JSON" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
chk "pinta el modelo"                  '[[ "$salida" == *ModeloX* ]]'
chk "pinta el fichero cambiado"        '[[ "$salida" == *f.txt* ]]'
chk "el enlace lleva el token"         '[[ "$salida" == *"t=$(cat "$ESTADO/token")"* ]]'
chk "token de 32 caracteres"           '[ "$(wc -c <"$ESTADO/token" | tr -d " ")" = 32 ]'
perm_f=$(stat -c %a "$ESTADO/token" 2>/dev/null || stat -f %Lp "$ESTADO/token")
perm_d=$(stat -c %a "$ESTADO" 2>/dev/null || stat -f %Lp "$ESTADO")
chk "token con permisos 600"           '[ "$perm_f" = 600 ]'
chk "carpeta de estado con permisos 700" '[ "$perm_d" = 700 ]'

espera_servidor
chk "el servidor responde 403 sin token" '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/ayuda")" = 403 ]'
chk "el servidor responde 200 con token" '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/ayuda?t=$(cat "$ESTADO/token")")" = 200 ]'

pid1=$(cat "$ESTADO/server.pid")
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1; sleep 0.5
chk "sin cambios no reinicia el servidor" '[ "$(cat "$ESTADO/server.pid")" = "$pid1" ]'

echo "# actualizado" >>"$TMP/diffserver.py"
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1; sleep 1; espera_servidor
chk "tras actualizar reinicia el servidor" '[ "$(cat "$ESTADO/server.pid")" != "$pid1" ]'
chk "y el servidor nuevo responde"         'nc -z -w 1 127.0.0.1 "$STATUSLINE_PORT" >/dev/null 2>&1'

# Conflictos de merge: UU y AA (añadido por ambos) deben pintarse como U rojo
G=(git -C "$TMP/repo" -c user.email=t@e.c -c user.name=t)
"${G[@]}" add -A; "${G[@]}" commit -qm base
base=$("${G[@]}" symbolic-ref --short HEAD)
"${G[@]}" checkout -qb ramaA; echo A >"$TMP/repo/f.txt"; echo A >"$TMP/repo/g.txt"; "${G[@]}" add -A; "${G[@]}" commit -qm A
"${G[@]}" checkout -q "$base"; echo B >"$TMP/repo/f.txt"; echo B >"$TMP/repo/g.txt"; "${G[@]}" add -A; "${G[@]}" commit -qm B
"${G[@]}" merge ramaA >/dev/null 2>&1
salida=$(echo "$JSON" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
rojoU=$'\033[31mU\033[0m'
chk "hay conflicto UU o AA en el repo de prueba" '"${G[@]}" status --porcelain | grep -qE "^(UU|AA) "'
chk "los conflictos se pintan como U rojo" '[ "$(grep -oF "$rojoU" <<<"$salida" | wc -l | tr -d " ")" = 2 ]'

# Algunos lanzadores (p. ej. los runners de macOS) arrancan los procesos con SIGPIPE ignorado:
# el token no debe generarse con tuberías que dependan de esa señal.
rm -rf "$XDG_STATE_HOME/sigpipe"; mkdir -p "$XDG_STATE_HOME/sigpipe"
chk "con SIGPIPE ignorado termina (no se cuelga) y genera el token" 'XDG_STATE_HOME="$XDG_STATE_HOME/sigpipe" perl -e '"'"'$SIG{PIPE}="IGNORE"; alarm 20; exec @ARGV'"'"' -- "$TMP/statusline.sh" >/dev/null 2>&1 <<<"$JSON" && [ "$(wc -c <"$XDG_STATE_HOME/sigpipe/claude-code-statusline/token" | tr -d " ")" = 32 ]'

# Prompt cache (5 min TTL), spend rate and re-cache warning. No repo: line 2 only.
SIN_GIT='{"model":{"display_name":"Opus"},"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":200000}},"cost":{"total_cost_usd":3.0,"total_duration_ms":1800000}'
touch "$TMP/t_fresco.jsonl"; touch -t 200001010000 "$TMP/t_viejo.jsonl"
fresco=$(echo "$SIN_GIT,\"transcript_path\":\"$TMP/t_fresco.jsonl\"}" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
viejo=$(echo "$SIN_GIT,\"transcript_path\":\"$TMP/t_viejo.jsonl\"}" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
ninguno=$(echo "$SIN_GIT}" | timeout_run "$TMP/statusline.sh" 2>/dev/null)
chk "live cache: shows the expiry time ↺HH:MM" '[[ "$fresco" =~ ↺[0-9][0-9]:[0-9][0-9] ]]'
chk "live cache: no re-cache warning"                    '[[ "$fresco" != *expired* ]]'
chk "expired cache: warns with context size and cost"  '[[ "$viejo" == *"expired"*"200.0k"*"\$1.25"* ]]'
chk "no transcript: no countdown and no warning"        '[[ "$ninguno" != *↺* && "$ninguno" != *expired* ]]'
chk "spend rate: \$3 in 30 min = \$6/h"              '[[ "$fresco" == *"\$6/h"* ]]'
chk "STATUSLINE_RECACHE_USD_PER_MTOK changes the cost"   '[[ "$(echo "$SIN_GIT,\"transcript_path\":\"$TMP/t_viejo.jsonl\"}" | STATUSLINE_RECACHE_USD_PER_MTOK=10 timeout_run "$TMP/statusline.sh" 2>/dev/null)" == *"\$2.00"* ]]'

chk "--version funciona"  '"$TMP/statusline.sh" --version | grep -q "^claude-code-statusline [0-9]"'
chk "--doctor funciona"   '"$TMP/statusline.sh" --doctor >/dev/null'

[ "$fallos" -eq 0 ] && echo "OK" || { echo "$fallos fallo(s)"; exit 1; }
