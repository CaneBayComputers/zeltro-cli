#!/bin/bash
# Test for the starter credit ("sandbox"): the hardware id, `zeltro sandbox
# claim/status` against a local mock of the license server, and how the credit
# steps in only while no AI is chosen. Uses a throwaway config dir; touches
# neither /etc/zeltro-cli nor the real server.
#
#   bash tests/sandbox.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { # <description> <actual> <expected>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi
}
field() { python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print(json.dumps(v) if isinstance(v,bool) or v is None else v)' "$1" "$2" 2>/dev/null; }

TMPD="$(mktemp -d)"
export XDG_CONFIG_HOME="$TMPD/config"
STATE="$TMPD/state"   # the mock's mode: ok | budget | used
echo ok > "$STATE"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')

python3 - "$PORT" "$STATE" "$TMPD/requests" <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port, state, log = int(sys.argv[1]), sys.argv[2], sys.argv[3]
claims = {}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body):
        b = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        open(log, "a").write(json.dumps(body) + "\n")
        mode = open(state).read().strip()
        if mode == "budget":
            return self.send(402, {"status": "error", "code": "sandbox_budget_exhausted", "error": "x"})
        m = body.get("machine", "")
        if len(m) != 64:
            return self.send(400, {"status": "error", "code": "bad_request", "error": "x"})
        new = m not in claims
        claims[m] = claims.get(m, 0) + 1
        self.send(200, {"status": "ok", "token": "zsb_test%d" % claims[m],
                        "api_base": "http://127.0.0.1:%d/api/v1/sandbox/openai" % port,
                        "model": "deepseek/deepseek-v4.1-flash", "agent": "opencode",
                        "credit_usd": 1.0, "new": new})
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        mode = open(state).read().strip()
        if not auth.startswith("Bearer zsb_"):
            return self.send(401, {"error": {"code": "invalid_token", "type": "x", "message": "x"}})
        left = 0.0 if mode == "used" else 0.75
        self.send(200, {"credit_usd": 1.0, "used_usd": 1.0 - left, "remaining_usd": left})
HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null; rm -rf "$TMPD"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.2; done
export ZELTRO_SANDBOX_SERVER="http://127.0.0.1:$PORT"

# Runs a snippet with functions.sh loaded and the .env's AI settings cleared,
# as on a fresh install.
fns() { ( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1
          AI_AGENT="" AI_MODEL="" AI_API_BASE="" AI_API_KEY=""; eval "$1" ); }

echo "Hardware id"
UUID=4C4C4544-0047-3510-8052-B2C04F334B32
a=$(ZELTRO_HARDWARE_ID=$UUID fns 'zeltro_hardware_id')
b=$(ZELTRO_HARDWARE_ID=$(echo $UUID | tr 'A-F' 'a-f') fns 'zeltro_hardware_id')
check "a UUID becomes a hash, not the UUID itself" "$(echo "$a" | grep -c "$UUID")" "0"
check "upper and lower case give the same id" "$a" "$b"
check "id is tagged dmi-sha256" "${a%%:*}" "dmi-sha256"
z=$(ZELTRO_HARDWARE_ID=00000000-0000-0000-0000-000000000000 fns 'zeltro_hardware_id')
check "an all-zero UUID is ignored" "$([ "$z" != "$a" ] && [ -n "$z" ] && echo skipped)" "skipped"
f=$(ZELTRO_HARDWARE_ID=03000200-0400-0500-0006-000700080009 fns 'zeltro_hardware_id')
check "the well-known filler UUID is ignored" "$([ "$f" = "$z" ] && echo skipped)" "skipped"
m=$(ZELTRO_HARDWARE_ID=$UUID fns 'zeltro_sandbox_machine')
check "machine value is 64 hex" "$(echo "$m" | grep -cE '^[0-9a-f]{64}$')" "1"
check "machine value is stable" "$m" "$(ZELTRO_HARDWARE_ID=$UUID fns 'zeltro_sandbox_machine')"

echo "status before a claim"
out=$(ZELTRO_HARDWARE_ID=$UUID "$REPO/src/zeltro" sandbox status --json-output)
check "not claimed" "$(field "$out" claimed)" "false"

echo "claim"
out=$(ZELTRO_HARDWARE_ID=$UUID "$REPO/src/zeltro" sandbox claim --json-output 2>/dev/null)
check "claim succeeds" "$(field "$out" status)" "success"
check "first claim is new" "$(field "$out" new)" "true"
check "credit reported" "$(field "$out" credit_usd)" "1.0"
check "token never printed" "$(echo "$out" | grep -c zsb_)" "0"
check "sent the machine hash" "$(tail -1 "$TMPD/requests" | python3 -c 'import json,sys; print(json.load(sys.stdin)["machine"])')" "$m"
FILE="$XDG_CONFIG_HOME/zeltro/sandbox.json"
check "saved privately (600)" "$(stat -c %a "$FILE" 2>/dev/null || stat -f %Lp "$FILE")" "600"
out=$(ZELTRO_HARDWARE_ID=$UUID "$REPO/src/zeltro" sandbox claim --json-output 2>/dev/null)
check "second claim is not new" "$(field "$out" new)" "false"
check "newest token kept" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$FILE")" "zsb_test2"

echo "the credit steps in only while no AI is chosen"
check "no AI chosen: sandbox active" \
    "$(fns 'zeltro_apply_sandbox_default; echo "$ZELTRO_SANDBOX_ACTIVE $AI_AGENT $AI_MODEL $AI_API_KEY"')" \
    "1 opencode deepseek/deepseek-v4.1-flash zsb_test2"
check "own AI chosen: untouched" \
    "$(fns 'AI_AGENT=claude; zeltro_apply_sandbox_default; echo "$ZELTRO_SANDBOX_ACTIVE $AI_AGENT"')" "0 claude"
check "ZELTRO_SANDBOX=0: off" \
    "$(ZELTRO_SANDBOX=0 fns 'zeltro_apply_sandbox_default; echo "$ZELTRO_SANDBOX_ACTIVE"')" "0"
check "a per-run override wins" \
    "$(fns 'ZELTRO_AI_OVERRIDE_ACTIVE=1; zeltro_apply_sandbox_default; echo "$ZELTRO_SANDBOX_ACTIVE"')" "0"
check "ai-set's view (no overrides) never sees it" \
    "$(fns 'ZELTRO_AI_NO_OVERRIDE=1; zeltro_apply_sandbox_default; echo "$ZELTRO_SANDBOX_ACTIVE"')" "0"
check "opencode is pointed at the proxy" \
    "$(fns 'zeltro_apply_sandbox_default; zeltro_opencode_prepare; echo "${ZELTRO_OPENCODE_ARGS[*]} $ZELTRO_AI_API_KEY"')" \
    "-m zeltro/deepseek/deepseek-v4.1-flash zsb_test2"

echo "status and the used-up check"
out=$("$REPO/src/zeltro" sandbox status --json-output)
check "balance read" "$(field "$out" remaining_usd)" "0.75"
check "not used up" "$(field "$out" used_up)" "false"
check "credit left: agent check passes" \
    "$(fns 'zeltro_apply_sandbox_default; command(){ return 0; }; zeltro_ai_agent_problem >/dev/null && echo pass')" "pass"
echo used > "$STATE"
out=$("$REPO/src/zeltro" sandbox status --json-output)
check "used up reported" "$(field "$out" used_up)" "true"
msg=$(fns 'zeltro_apply_sandbox_default; command(){ return 0; }; zeltro_ai_agent_problem')
check "used up: agent check stops with the message" "$(echo "$msg" | grep -c 'starter credit is used up')" "1"
check "and names ai-set" "$(echo "$msg" | grep -c 'zeltro ai-set')" "1"

echo "errors"
rm -f "$FILE"; echo budget > "$STATE"
out=$(ZELTRO_HARDWARE_ID=$UUID "$REPO/src/zeltro" sandbox claim --json-output 2>/dev/null); rc=$?
check "budget exhausted: error code" "$(field "$out" error)" "sandbox_budget_exhausted"
check "budget exhausted: non-zero exit" "$rc" "1"
check "nothing saved" "$([ -e "$FILE" ] && echo saved || echo none)" "none"
out=$(ZELTRO_SANDBOX_SERVER=http://127.0.0.1:1 ZELTRO_HARDWARE_ID=$UUID "$REPO/src/zeltro" sandbox claim --json-output 2>/dev/null)
check "server unreachable: error code" "$(field "$out" error)" "unreachable"
out=$(ZELTRO_SANDBOX=0 "$REPO/src/zeltro" sandbox claim --json-output 2>/dev/null)
check "ZELTRO_SANDBOX=0 refuses to claim" "$(field "$out" error)" "sandbox_off"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
