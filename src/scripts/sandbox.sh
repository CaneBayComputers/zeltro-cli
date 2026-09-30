#!/bin/bash
# zeltro sandbox — the complimentary starter credit.
#
#   zeltro sandbox [status] [--json-output]   Is there a credit, is it in use, how much is left
#   zeltro sandbox claim [--json-output]      Claim it for this computer (same credit on a reinstall)
#
# See the "Starter credit" block in functions.sh for how it plugs in. The token
# is never printed, in either output mode.

set -e

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

source scripts/functions.sh

ACTION="status"
JSON_OUTPUT="${JSON_OUTPUT:-0}"

usage() {
    echo-white "Usage: zeltro sandbox [status|claim] [--json-output]"
    echo-white ""
    echo-white "Zeltro's complimentary starter credit: AI for your first builds, before you"
    echo-white "set up your own. It is used only while no AI is chosen with 'zeltro ai-set',"
    echo-white "and Zeltro claims it by itself the first time it needs an AI."
    echo-white ""
    echo-white "  status   Show whether this computer has the credit and how much is left (default)"
    echo-white "  claim    Claim it now. A reinstall gets the same credit back, not a new one."
    echo-white ""
    echo-white "Set ZELTRO_SANDBOX=0 to never use it."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        status|claim) ACTION="$1"; shift ;;
        --json-output) JSON_OUTPUT=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *)
            if [[ "$JSON_OUTPUT" == "1" ]]; then
                python3 -c 'import json,sys; print(json.dumps({"action":"sandbox","status":"error","error":"bad_argument","message":"Unknown option: "+sys.argv[1]}))' "$1"
            else
                echo-red "Unknown option: $1"; usage
            fi
            exit 1
            ;;
    esac
done

SERVER="${ZELTRO_SANDBOX_SERVER%/}"
FILE="$(zeltro_sandbox_file)"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

fail() {
    # $1 = code, $2 = message
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c 'import json,sys; print(json.dumps({"action":"sandbox_"+sys.argv[1],"status":"error","error":sys.argv[2],"message":sys.argv[3]}))' "$ACTION" "$1" "$2"
    else
        echo-red "$2" >&2
    fi
    exit 1
}

# In use = no AI chosen, the credit is claimed, and nothing turned it off.
in_use_json() {
    ZELTRO_AI_NO_OVERRIDE=0
    zeltro_apply_sandbox_default
    [ "${ZELTRO_SANDBOX_ACTIVE:-0}" = "1" ] && echo true || echo false
}

if [[ "$ACTION" == "claim" ]]; then
    [ "${ZELTRO_SANDBOX:-1}" = "0" ] && fail "sandbox_off" "The starter credit is turned off here (ZELTRO_SANDBOX=0)."

    MACHINE=$(zeltro_sandbox_machine) || fail "no_machine_id" "Couldn't work out a hardware id for this computer, so the starter credit can't be claimed. Choose your own AI with 'zeltro ai-set'."

    [[ "$JSON_OUTPUT" == "1" ]] || echo-cyan "Claiming your Zeltro starter credit..."
    BODY=$(python3 -c 'import json,sys; print(json.dumps({"machine":sys.argv[1],"cli_version":sys.argv[2]}))' "$MACHINE" "$(zeltro_version 2>/dev/null || echo unknown)")
    HTTP=$(curl -sS --max-time 25 --connect-timeout 8 -o "$TMP" -w '%{http_code}' \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        -X POST --data "$BODY" "$SERVER/api/v1/sandbox" 2>/dev/null) || HTTP="000"

    if [[ "$HTTP" != "200" ]]; then
        CODE=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("code") or "")
except Exception: print("")' "$TMP")
        case "$CODE" in
            sandbox_disabled)         MSG="The starter credit isn't available right now." ;;
            sandbox_revoked)          MSG="The starter credit for this computer has been switched off." ;;
            sandbox_budget_exhausted) MSG="Today's starter credits are all given out. Try again tomorrow, or choose your own AI now." ;;
            rate_limited)             MSG="Too many requests from this network. Try again in a little while." ;;
            provider_error)           MSG="The AI provider didn't respond. Try again in a minute." ;;
            "")                       CODE="unreachable"; MSG="Couldn't reach the Zeltro server (HTTP $HTTP)." ;;
            *)                        MSG="The Zeltro server declined the request ($CODE)." ;;
        esac
        fail "$CODE" "$MSG Meanwhile you can use your own AI: Settings → AI in the app, or 'zeltro ai-set'."
    fi

    # Save it: private file, written atomically. The server rotates the token
    # on every claim, so the newest one always replaces the old.
    mkdir -p "$(dirname "$FILE")"
    RESULT=$(umask 077; python3 - "$TMP" "$FILE" "$SERVER" <<'PY'
import json, os, sys, time
src, dest, server = sys.argv[1:4]
d = json.load(open(src))
if d.get("status") != "ok" or not d.get("token") or not d.get("api_base"):
    print(json.dumps({"ok": False}))
    sys.exit(0)
keep = {
    "token": d["token"], "api_base": d["api_base"],
    "model": d.get("model") or "", "agent": d.get("agent") or "opencode",
    "credit_usd": d.get("credit_usd"), "server": server,
    "claimed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
tmp = dest + ".tmp"
with open(tmp, "w") as fh:
    json.dump(keep, fh, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, dest)
print(json.dumps({"ok": True, "new": bool(d.get("new")), "credit_usd": d.get("credit_usd"),
                  "model": keep["model"], "agent": keep["agent"]}))
PY
)
    python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1])["ok"] else 1)' "$RESULT" \
        || fail "bad_response" "The Zeltro server sent an answer this version doesn't understand. Try 'zeltro update'."

    AGENT=$(zeltro_sandbox_field agent)
    INSTALLED=true
    if ! zeltro_agent_installed "$AGENT"; then
        [[ "$JSON_OUTPUT" == "1" ]] || echo-cyan "Installing $AGENT to use it..."
        "$ZELTRO_SRC_DIR/scripts/ai_set.sh" --install-only --agent "$AGENT" --json-output >/dev/null 2>&1 || true
        zeltro_agent_installed "$AGENT" || INSTALLED=false
    fi

    IN_USE=$(in_use_json)
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c '
import json, sys
r = json.loads(sys.argv[1])
print(json.dumps({"action": "sandbox_claim", "status": "success", "new": r["new"],
                  "credit_usd": r["credit_usd"], "agent": r["agent"], "model": r["model"],
                  "agent_installed": sys.argv[2] == "true", "in_use": sys.argv[3] == "true"}))
' "$RESULT" "$INSTALLED" "$IN_USE"
    else
        CREDIT=$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print("%.2f" % float(r["credit_usd"] or 0))' "$RESULT")
        echo-green "Starter credit ready: \$$CREDIT of AI, on us."
        if [[ "$INSTALLED" != "true" ]]; then
            echo-yellow "Couldn't install $AGENT, which the credit runs on. Try: zeltro ai-set --install-only --agent $AGENT"
        elif [[ "$IN_USE" == "true" ]]; then
            echo-white "Zeltro will use it until you choose your own AI (Settings → AI, or 'zeltro ai-set')."
        else
            echo-white "You already have your own AI set up, so Zeltro keeps using that."
        fi
    fi
    exit 0
fi

# status
if [ ! -r "$FILE" ]; then
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        echo '{"action": "sandbox_status", "status": "success", "claimed": false, "in_use": false}'
    else
        echo-white "No starter credit claimed on this computer. Zeltro claims it by itself the first time it"
        echo-white "needs an AI and none is set up, or run: zeltro sandbox claim"
    fi
    exit 0
fi

TOKEN=$(zeltro_sandbox_field token || true)
HTTP=$(curl -sS --max-time 10 --connect-timeout 5 -o "$TMP" -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' \
    "$SERVER/api/v1/sandbox/status" 2>/dev/null) || HTTP="000"
IN_USE=$(in_use_json)

python3 - "$TMP" "$HTTP" "$IN_USE" "$JSON_OUTPUT" "$ZELTRO_SANDBOX_USED_UP_MESSAGE" <<'PY'
import json, sys
path, http, in_use, as_json, used_up = sys.argv[1:6]
out = {"action": "sandbox_status", "status": "success", "claimed": True, "in_use": in_use == "true"}
try:
    body = json.load(open(path))
except Exception:
    body = {}
if http == "200" and "remaining_usd" in body:
    out.update(credit_usd=body.get("credit_usd"), used_usd=body.get("used_usd"),
               remaining_usd=body.get("remaining_usd"))
    out["used_up"] = float(body.get("remaining_usd") or 0) <= 0.001
    if out["used_up"]:
        out["message"] = used_up
else:
    err = body.get("error") if isinstance(body.get("error"), dict) else {}
    code = err.get("code") or body.get("code") or ("unreachable" if http == "000" else "http_%s" % http)
    out["balance_error"] = code
    if code == "invalid_token":
        out["message"] = "This credit was claimed again from another install on this computer. Run 'zeltro sandbox claim' to use it here."
    elif code in ("sandbox_revoked", "sandbox_disabled"):
        out["message"] = "The starter credit is switched off."
    elif code == "sandbox_credit_exhausted":
        out["used_up"] = True
        out["message"] = used_up
    else:
        out["message"] = "Couldn't check the balance right now."
if as_json == "1":
    print(json.dumps(out))
    sys.exit(0)
if "remaining_usd" in out:
    print("Starter credit: $%.2f left of $%.2f." % (float(out["remaining_usd"] or 0), float(out["credit_usd"] or 0)))
else:
    print("Starter credit: claimed.")
if out.get("message"):
    print(out["message"])
if not out.get("used_up"):
    print("In use: yes, until you choose your own AI." if out["in_use"] else
          "In use: no. Your own AI is set up (or ZELTRO_SANDBOX=0), so Zeltro uses that.")
PY
