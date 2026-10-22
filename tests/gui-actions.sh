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
    "ask":      lambda a: {"status": "ok", "result": {"answer": "my own words", "typed": True}}
                          if a["question"].startswith("type") else
                          {"status": "ok", "result": {"answer": a["options"][-1], "typed": False}},
    "secret":   lambda a: {"status": "ok", "result": {"value": "s3cr3t with 'quote"}} if a["name"] != "NOPE"
                          else {"status": "declined"},
    "settings": lambda a: {"status": "ok", "result": {}},
    "screenshot": lambda a: {"status": "refused", "error": "the capture was empty"} if a.get("path") == "/blank"
                            else {"status": "ok", "result": {"file": ".zeltro-uploads/screenshot-1.png",
                                                             "url": "http://10.0.0.5" + a.get("path", "/")}},
    "report":   lambda a: {"status": "ok", "result": {"sent": True}},
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
[ "$(ls "$ZELTRO_BUS_DIR/gui/cancel" | wc -l)" = 1 ] && ok "picked-up request cancelled" || bad "no cancel marker"
rm -f "$ZELTRO_BUS_DIR"/gui/cancel/*
kill -STOP $APP_PID    # the app is busy: the request is still unread when the caller gives up
expect_code 4 "ask times out unread" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "Q?" --option A --timeout 1
kill -CONT $APP_PID
[ -z "$(ls "$ZELTRO_BUS_DIR/gui/requests")" ] && [ -z "$(ls "$ZELTRO_BUS_DIR/gui/cancel")" ] \
    && ok "unread request deleted, no cancel needed" || bad "unread timeout left files"

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

expect_code 0 "ask --allow-text, no options" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "type anything?" --allow-text
[ "$(cat "$T/out")" = "my own words" ] && ok "typed answer printed" || bad "typed ask printed '$(cat "$T/out")'"
grep -q '"allow_text": true' "$T/seen" && ok "allow_text sent" || bad "allow_text missing: $(tail -1 "$T/seen")"
expect_code 0 "ask --allow-text, picked an option" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "Which?" --option Red --option Blue --allow-text
[ "$(cat "$T/out")" = "Blue" ] && ok "picked answer printed" || bad "ask printed '$(cat "$T/out")'"
expect_code 1 "typed answer without --allow-text rejected" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" ask "type?" --option A
expect_code 0 "ask --allow-text JSON" env ZELTRO_GUI_SESSION=s1 "$ZELTRO" gui ask "type?" --allow-text --json-output
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["typed"] is True and d["answer"] == "my own words" else 1)' "$T/out" \
    && ok "JSON carries typed" || bad "JSON: $(cat "$T/out")"

: > "$T/seen"
expect_code 0 "preview" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" preview
expect_code 0 "preview --path" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" preview --path /pricing
sleep 0.3
[ "$(grep -c '"action": "preview"' "$T/seen")" = 2 ] && grep -q '"path": "/pricing"' "$T/seen" \
    && ok "preview requests delivered" || bad "preview seen: $(cat "$T/seen")"
[ -z "$(ls "$ZELTRO_BUS_DIR/gui/replies")" ] && ok "preview waits for no reply" || bad "reply left"
expect_code 2 "preview --path needs a /page" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" preview --path https://x.example/
expect_code 3 "preview outside an app session" python3 "$GUI" preview

: > "$T/seen"
expect_code 0 "screenshot" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" screenshot --path /pricing
[ "$(cat "$T/out")" = ".zeltro-uploads/screenshot-1.png" ] && ok "screenshot prints the file" || bad "screenshot printed '$(cat "$T/out")'"
expect_code 0 "screenshot JSON" env ZELTRO_GUI_SESSION=s1 "$ZELTRO" gui screenshot --json-output
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["file"].endswith(".png") and d["url"] == "http://10.0.0.5/" else 1)' "$T/out" \
    && ok "JSON has file and url" || bad "JSON: $(cat "$T/out")"
expect_code 6 "screenshot refused (empty capture)" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" screenshot --path /blank
grep -q "empty" "$T/err" && ok "refusal reason printed" || bad "stderr: $(cat "$T/err")"
expect_code 2 "screenshot bad path" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" screenshot --path pricing
expect_code 0 "report" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" report "$(head -c 300 /dev/zero | tr '\0' t)" --details "ran zeltro up; got exit 1"
python3 - "$T/seen" <<'EOF' && ok "report args (title cut to 200)" || bad "report seen: $(grep report "$T/seen")"
import json, sys
r = [json.loads(l) for l in open(sys.argv[1]) if '"report"' in l][0]["args"]
sys.exit(0 if len(r["title"]) == 200 and r["details"] == "ran zeltro up; got exit 1" else 1)
EOF
expect_code 2 "report needs a title" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" report ""
expect_code 3 "report outside an app session" python3 "$GUI" report "x"

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

echo "status and turn-done messages:"
: > "$T/seen"
expect_code 0 "status" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" status "Adding a pricing page."
expect_code 2 "status needs text" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" status "  "
expect_code 3 "status outside an app session" python3 "$GUI" status "x"
expect_code 0 "status, long" env ZELTRO_GUI_SESSION=s1 python3 "$GUI" status "$(head -c 3000 /dev/zero | tr '\0' a)"
sleep 0.3
python3 - "$T/seen" <<'EOF' && ok "status text sent, long one cut to 2000" || bad "status requests: $(cat "$T/seen")"
import json, sys
st = [json.loads(l)["args"]["text"] for l in open(sys.argv[1]) if '"status"' in l]
sys.exit(0 if st[0] == "Adding a pricing page." and len(st[1]) == 2000 and st[1].endswith("\u2026") else 1)
EOF
: > "$T/seen"
(cd "$PROJ" && ZELTRO_GUI_SESSION=m1 "$ZELTRO" gui event turn-done '{"type":"agent-turn-complete","last-assistant-message":"Codex says done."}' </dev/null)
echo '{"hook_event_name":"Stop","last_assistant_message":"  Claude says done.\n"}' | (cd "$PROJ" && ZELTRO_GUI_SESSION=m2 "$ZELTRO" gui event turn-done)
cat > "$T/transcript.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"hi"}}
{"type":"assistant","message":{"id":"m_old","content":[{"type":"text","text":"Earlier reply."}]}}
{"type":"user","message":{"role":"user","content":"make it blue"}}
{"type":"assistant","message":{"id":"m_new","content":[{"type":"text","text":"Made the header blue."}]}}
{"type":"assistant","message":{"id":"m_new","content":[{"type":"text","text":"Reload to see it."}]}}
{"type":"system","subtype":"stop_hook_summary"}
EOF
echo "{\"transcript_path\":\"$T/transcript.jsonl\"}" | (cd "$PROJ" && ZELTRO_GUI_SESSION=m3 "$ZELTRO" gui event turn-done)
echo '{"message":"Claude needs your permission"}' | (cd "$PROJ" && ZELTRO_GUI_SESSION=m4 "$ZELTRO" gui event needs-input)
(cd "$PROJ" && ZELTRO_GUI_SESSION=m5 "$ZELTRO" gui event turn-done </dev/null)
sleep 0.3
python3 - "$T/seen" <<'EOF' && ok "turn-done carries the last reply (codex, claude, transcript); others don't" || bad "events: $(cat "$T/seen")"
import json, sys
got = {r["from"]["session"]: r["args"].get("message") for r in map(json.loads, open(sys.argv[1]))}
want = {"m1": "Codex says done.", "m2": "Claude says done.",
        "m3": "Made the header blue.\nReload to see it.", "m4": None, "m5": None}
sys.exit(0 if got == want else print(got) or 1)
EOF
expect_code 0 "event with a broken bus" env ZELTRO_GUI_SESSION=s1 ZELTRO_BUS_DIR=/proc/nope "$ZELTRO" gui event turn-done

perm=$(stat -c %a "$ZELTRO_BUS_DIR/gui/requests" 2>/dev/null || stat -f %Lp "$ZELTRO_BUS_DIR/gui/requests")
[ "$perm" = 700 ] && ok "requests dir is 0700" || bad "requests dir is $perm"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
