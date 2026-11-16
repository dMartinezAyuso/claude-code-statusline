#!/bin/bash
# Regenerates the images of the README (docs/images/*.png) from a throwaway repository with many changed files.
# Needs Google Chrome (or set CHROME=/path/to/chrome) for the headless screenshot.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/images"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || CHROME=$(command -v google-chrome chromium chromium-browser 2>/dev/null | head -1)
[ -n "$CHROME" ] || { echo "Chrome not found: set CHROME=/path/to/chrome" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'kill "$(cat "$TMP/state/claude-code-statusline/server.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# Demo repository: a feature branch with changed, added, deleted, renamed and untracked files
REPO="$TMP/checkout-service"; git init -q -b main "$REPO"; cd "$REPO"
export GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com
mkdir -p src/api src/models src/utils tests docs
for f in src/api/orders.py src/api/payments.py src/api/users.py src/models/order.py src/models/user.py src/models/cart.py \
         src/utils/money.py src/utils/dates.py tests/test_orders.py tests/test_payments.py tests/test_cart.py docs/api.md README.md legacy.py; do
  echo "# $f" >"$f"; done
git add -A && git commit -q -m init && git checkout -q -b PROJ-1234-refactor-checkout
for f in src/api/orders.py src/api/payments.py src/api/users.py src/models/order.py src/models/user.py src/utils/money.py \
         src/utils/dates.py tests/test_orders.py tests/test_payments.py docs/api.md README.md; do echo "change" >>"$f"; done
git rm -q legacy.py; git mv src/models/cart.py src/models/basket.py
for f in src/api/refunds.py src/api/webhooks.py src/models/refund.py src/utils/retry.py tests/test_refunds.py tests/test_webhooks.py \
         docs/refunds.md CHANGELOG.md; do echo "new" >"$f"; done
git add src/api/refunds.py src/models/refund.py tests/test_refunds.py

# Account and state: an isolated config, so nothing of the real account or machine appears
mkdir -p "$TMP/cfg"
echo '{"oauthAccount":{"emailAddress":"alex.rivera@example.com","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}' >"$TMP/cfg/.claude.json"
export XDG_STATE_HOME="$TMP/state" CLAUDE_CONFIG_DIR="$TMP/cfg" COLUMNS=118 STATUSLINE_LANG=en
STATUSLINE_PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'); export STATUSLINE_PORT
now=$(date +%s)
JSON='{"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"workspace":{"current_dir":"'"$REPO"'"},
"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":2000,"cache_creation_input_tokens":9000,"cache_read_input_tokens":164000},"total_input_tokens":1840000,"total_output_tokens":96000},
"cost":{"total_cost_usd":18.42,"total_duration_ms":5280000,"total_lines_added":612,"total_lines_removed":148},
"rate_limits":{"five_hour":{"used_percentage":43,"resets_at":'$((now + 8100))'},"seven_day":{"used_percentage":21,"resets_at":'$((now + 3*86400 + 7200))'}},
"prompt_cache":{"hit_ratio":0.94,"expires_at":'$((now + 240))',"recache_tokens_if_cold":175000},"pr":{"number":482,"review_state":"approved"}}'

render() {   # render <name> [VAR=value...]
  local name=$1; shift
  echo "$JSON" | ( [ $# -gt 0 ] && export "$@"; "$ROOT/statusline.sh" ) >"$TMP/$name.ansi"
  python3 -I "$ROOT/scripts/ansi2html.py" <"$TMP/$name.ansi" >"$TMP/$name.html"
  # Window sized to the content: the widest line (in characters) and the number of lines, at 15px Menlo
  local size; size=$(perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\a]*\a//g' "$TMP/$name.ansi" | python3 -I -c '
import sys
ls = sys.stdin.read().rstrip("\n").split("\n")
print(int(max(len(l) for l in ls) * 9.03 + 52), int(len(ls) * 22.5 + 40))')
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size="${size// /,}" \
    --screenshot="$OUT/$name.png" "file://$TMP/$name.html" >/dev/null 2>&1
  echo "wrote docs/images/$name.png ($size)"
}
render statusline-compact
render statusline-count STATUSLINE_FILES=count
