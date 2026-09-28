#!/bin/bash
# End-to-end test for `zeltro gui`: a fake app answers requests on a scratch bus.
# Needs no Docker and touches nothing outside a temp dir. Run from anywhere:
#   bash tests/gui-actions.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
GUI="$REPO/src/scripts/gui.py"
ZELTRO="$REPO/src/zeltro"
T="$(mktemp -d)"
trap 'kill $APP_PID 2>/dev/null; rm -rf "$T"' EXIT

export ZELTRO_BUS_DIR="$T/bus"
export ZELTRO_PROJECTS_DIR="$T/projects"
mkdir -p "$ZELTRO_BUS_DIR" "$ZELTRO_PROJECTS_DIR/demo"
PROJ="$ZELTRO_PROJECTS_DIR/demo"
APP_PID=""
pass=0; fail=0

ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
expect_code() { # <want> <label> <cmd...>
    local want="$1" label="$2"; shift 2
    local got; (cd "$PROJ" && "$@") >"$T/out" 2>"$T/err"; got=$?
    if [ "$got" = "$want" ]; then ok "$label (exit $got)"; else bad "$label: exit $got, wanted $want. $(cat "$T/err")"; fi
}

heartbeat() {
    python3 - "$ZELTRO_BUS_DIR/peers.json" <<'EOF'
import json, sys
from datetime import datetime, timezone
json.dump({"version": 1, "updated_at": datetime.now(timezone.utc).isoformat(),
           "this_host": "testhost", "sessions": []}, open(sys.argv[1], "w"))
EOF
}

# The fake app: answers by action, and records what it saw.
start_app() {
    python3 - "$ZELTRO_BUS_DIR" "$T/seen" <<'EOF' &
import json, os, sys, time
bus, seen = sys.argv[1], sys.argv[2]
req, rep = os.path.join(bus, "gui", "requests"), os.path.join(bus, "gui", "replies")
answers = {
    "ask":      lambda a: {"status": "ok", "result": {"answer": a["options"][-1]}},
    "secret":   lambda a: {"status": "ok", "result": {"value": "s3cr3t with 'quote"}} if a["name"] != "NOPE"
                          else {"status": "declined"},
    "settings": lambda a: {"status": "ok", "result": {}},
    "open":     lambda a: {"status": "refused", "error": "not the project's URL"} if "evil" in a.get("url", "")
                          else {"status": "ok", "result": {}},
}
while True:
    if os.path.isdir(req):
        for n in sorted(os.listdir(req)):
            if not n.endswith(".json"):
                continue
            p = os.path.join(req, n)
            r = json.load(open(p))
            os.unlink(p)
            with open(seen, "a") as f:
                f.write(json.dumps(r) + "\n")
            if r["action"] in answers and not r["args"].get("question", "").startswith("slow"):
                out = dict(answers[r["action"]](r["args"]), version=1, id=r["id"])
                tmp = os.path.join(rep, r["id"] + ".json.tmp")
                json.dump(out, open(tmp, "w"))
                os.replace(tmp, os.path.join(rep, r["id"] + ".json"))
    time.sleep(0.05)
EOF
    APP_PID=$!
}

echo "No app running:"
expect_code 3 "ask without the app" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "Q?" --option A
expect_code 0 "event without the app" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" event turn-done
[ ! -d "$ZELTRO_BUS_DIR/gui/requests" ] || [ -z "$(ls "$ZELTRO_BUS_DIR/gui/requests")" ] \
    && ok "event without the app writes nothing" || bad "event without the app left a file"

heartbeat
start_app
echo "App running:"
expect_code 2 "usage: no options"      python3 "$GUI" ask "Q?"
expect_code 2 "usage: bad default"     python3 "$GUI" ask "Q?" --option A --default B
expect_code 2 "usage: unknown action"  python3 "$GUI" frob
expect_code 3 "ask outside an app session" python3 "$GUI" ask "Q?" --option A

expect_code 0 "ask" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "Which?" --option Red --option Blue
[ "$(cat "$T/out")" = "Blue" ] && ok "ask prints the answer" || bad "ask printed '$(cat "$T/out")'"
grep -q '"session": "s1"' "$T/seen" && grep -q '"project": "demo"' "$T/seen" \
    && ok "request carries project and session" || bad "request from{} is wrong: $(tail -1 "$T/seen")"

expect_code 4 "ask times out" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "slow?" --option A --timeout 1
[ -z "$(ls "$ZELTRO_BUS_DIR/gui/requests")" ] && ok "timed-out request withdrawn" || bad "request left behind"

printf 'APP_KEY=abc\nAPI_KEY=old\nexport API_KEY=older\n' > "$PROJ/.env"
expect_code 0 "secret" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" secret API_KEY
grep -qx "API_KEY=\"s3cr3t with 'quote\"" "$PROJ/.env" && [ "$(grep -c API_KEY "$PROJ/.env")" = 1 ] \
    && grep -qx 'APP_KEY=abc' "$PROJ/.env" && ok "secret upserted once, rest kept" || bad "secret .env: $(cat "$PROJ/.env")"
grep -q s3cr3t "$T/out" "$T/err" && bad "secret value was printed" || ok "secret value not printed"
[ -z "$(ls "$ZELTRO_BUS_DIR/gui/replies")" ] && ok "reply file deleted" || bad "reply file left behind"
expect_code 6 "secret outside the project" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" secret X --file ../../escape.env
ln -s "$T" "$PROJ/link"
expect_code 6 "secret through a symlink out" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" secret X --file link/x.env
expect_code 5 "secret declined" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" secret NOPE
expect_code 2 "secret bad name" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" secret 1BAD

expect_code 0 "settings" python3 "$GUI" settings ai --reason "add a key"
expect_code 2 "settings bad tab" python3 "$GUI" settings nope
expect_code 0 "open project" python3 "$GUI" open --project
expect_code 6 "open refused by app" python3 "$GUI" open https://evil.example
expect_code 6 "open non-http" python3 "$GUI" open file:///etc/passwd
expect_code 0 "notify" python3 "$GUI" notify --level warning "Build broke" "see the log"

: > "$T/seen"
expect_code 0 "event" env ZELTRO_GUI_SESSION=s1 "$ZELTRO" gui event turn-done '{"type":"agent-turn-complete"}'
[ ! -s "$T/out" ] && ok "event prints nothing" || bad "event printed: $(cat "$T/out")"
expect_code 0 "event again (coalesced)" env ZELTRO_GUI_SESSION=s1 "$ZELTRO" gui event turn-done
expect_code 0 "event unknown type" env ZELTRO_GUI_SESSION=s1 "$ZELTRO" gui event bogus
sleep 0.5
[ "$(grep -c '"event"' "$T/seen")" = 1 ] && ok "one event delivered" || bad "events seen: $(grep -c '"event"' "$T/seen")"
expect_code 0 "event with a broken bus" env ZELTRO_GUI_SESSION=s1 ZELTRO_BUS_DIR=/proc/nope "$ZELTRO" gui event turn-done

perm=$(stat -c %a "$ZELTRO_BUS_DIR/gui/requests" 2>/dev/null || stat -f %Lp "$ZELTRO_BUS_DIR/gui/requests")
[ "$perm" = 700 ] && ok "requests dir is 0700" || bad "requests dir is $perm"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
