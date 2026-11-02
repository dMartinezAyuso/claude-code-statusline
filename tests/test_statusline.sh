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

sleep 1.5
chk "el servidor responde 403 sin token" '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/ayuda")" = 403 ]'
chk "el servidor responde 200 con token" '[ "$(curl -s --max-time 5 -o /dev/null -w %{http_code} "http://127.0.0.1:$STATUSLINE_PORT/ayuda?t=$(cat "$ESTADO/token")")" = 200 ]'

pid1=$(cat "$ESTADO/server.pid")
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1; sleep 0.5
chk "sin cambios no reinicia el servidor" '[ "$(cat "$ESTADO/server.pid")" = "$pid1" ]'

echo "# actualizado" >>"$TMP/diffserver.py"
echo "$JSON" | timeout_run "$TMP/statusline.sh" >/dev/null 2>&1; sleep 1.5
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

chk "--version funciona"  '"$TMP/statusline.sh" --version | grep -q "^claude-code-statusline [0-9]"'
chk "--doctor funciona"   '"$TMP/statusline.sh" --doctor >/dev/null'

[ "$fallos" -eq 0 ] && echo "OK" || { echo "$fallos fallo(s)"; exit 1; }
