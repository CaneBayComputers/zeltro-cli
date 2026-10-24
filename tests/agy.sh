#!/bin/bash
# The Antigravity CLI (agy), Google's replacement for Gemini CLI: default order,
# launch flags, the Gemini-key provider setting, unattended mode, folder trust,
# ai-status, and Gemini's deprecation. A fake agy on PATH and a sandboxed HOME;
# no network, never touches the real ~/.gemini.
#
#   bash tests/agy.sh
set -u
unset NVM_DIR

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

[ -f /etc/zeltro-cli/.env ] || { echo "skipped: needs a configured Zeltro (/etc/zeltro-cli/.env)"; exit 0; }

# The fake agy logs its arguments (one per line) and the key it saw, and
# answers `models` like agy 1.4.6: signed in when FAKE_AGY_SIGNED_IN=1.
mkdir -p "$T/bin" "$T/home/.local/bin"
cat > "$T/home/.local/bin/agy" <<FAKE
#!/bin/bash
case "\$1" in
    --version) echo "1.4.6"; exit 0 ;;
    models)
        if [ "\${FAKE_AGY_SIGNED_IN:-0}" = 1 ]; then printf 'gemini-3.1-pro-low\tGemini 3.1 Pro (Low)\n'
        else echo "Fetching available models..."; echo "Error: Please sign in to view available models. Launch the CLI without arguments to sign in."; fi
        exit 0 ;;
esac
{ echo "KEY=\${GEMINI_API_KEY:-}"; printf '%s\n' "\$@"; } > "$T/agy-args.log"
FAKE
chmod +x "$T/home/.local/bin/agy"
SET="$T/home/.gemini/antigravity-cli/settings.json"
mkdir -p "$T/home/projects"

sh_() { # <shell code>: functions.sh sourced, HOME sandboxed
    ( export HOME="$T/home" PATH="/usr/bin:/bin" NO_COLOR=1
      unset GEMINI_API_KEY ZELTRO_AI_AGENT
      cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1
      get_projects_dir() { echo "$T/home/projects"; }
      eval "$1" )
}
z() { # zeltro <args> with HOME sandboxed and the env assignments in ZENV
    ( export HOME="$T/home" PATH="/usr/bin:/bin" NO_COLOR=1; unset GEMINI_API_KEY
      env ${ZENV:-} "$REPO/src/zeltro" "$@" 2>/dev/null </dev/null )
}
jget() { python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print("<none>"); sys.exit()
for k in sys.argv[2].split("."): d = d.get(k) if isinstance(d, dict) else None
print(d)' "$1" "$2"; }
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1].strip().splitlines()[-1]); print(d.get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
# The arguments joined by |, with --add-dir's folder (the real PROJECTS_DIR) as D.
args() { tail -n +2 "$T/agy-args.log" 2>/dev/null | awk 'd { print "D"; d = 0; next } $0 == "--add-dir" { d = 1 } { print }' | tr '\n' '|'; }

echo "known agent, default order, deprecation"
check "agy is a known agent" "$(sh_ 'case " $ZELTRO_KNOWN_AI_AGENTS " in *" agy "*) echo yes ;; esac')" "yes"
check "display name" "$(sh_ 'zeltro_agent_display_name agy')" "Antigravity CLI"
check "agy is picked before gemini" "$(mkdir -p "$T/home/.npm-global/bin"; printf '#!/bin/sh\n' > "$T/home/.npm-global/bin/gemini"; chmod +x "$T/home/.npm-global/bin/gemini"; sh_ 'AI_AGENT=; zeltro_fill_default_agent; echo $AI_AGENT')" "agy"
rm -f "$T/home/.npm-global/bin/gemini"
check "gemini is deprecated" "$(sh_ 'zeltro_agent_deprecated gemini' | grep -c 'zeltro ai-set --agent agy')" "1"
check "agy is not" "$(sh_ 'zeltro_agent_deprecated agy')" ""
caps="$(python3 "$REPO/src/scripts/ai_auth.py" capabilities)"
check "capabilities: agy subscription, no endpoint" "$(python3 -c 'import json,sys; a=json.loads(sys.argv[1])["agents"]["agy"]; print(a["subscription"], a["api_key"], a["endpoint"])' "$caps")" "True True None"
check "capabilities: gemini replaced_by agy" "$(python3 -c 'import json,sys; g=json.loads(sys.argv[1])["agents"]["gemini"]; print(g["replaced_by"], bool(g["deprecated"]))' "$caps")" "agy True"

echo "launch flags"
ZENV="ZELTRO_AI_AGENT=agy ZELTRO_AI_MODEL=gemini-3.1-pro-low ZELTRO_AI_API_KEY=AIzaTEST ZELTRO_NO_AGENT_TRUST=1"
z ai --one-off "make a page" >/dev/null
check "one-off: flags, then -p and the prompt" "$(args)" "--model|gemini-3.1-pro-low|--add-dir|D|-p|make a page|"
check "key reaches GEMINI_API_KEY" "$(head -n 1 "$T/agy-args.log")" "KEY=AIzaTEST"
check "provider set for the key" "$(jget "$SET" modelProvider)" "gemini"
check "settings file is 600" "$(stat -c %a "$SET" 2>/dev/null || stat -f %Lp "$SET")" "600"
ZENV="ZELTRO_AI_AGENT=agy ZELTRO_AI_MODEL= ZELTRO_AI_API_KEY= ZELTRO_AI_AUTO_APPROVE=1"
z ai --interactive "make a page" >/dev/null
check "interactive: -i; AUTO_APPROVE adds the bypass flag" "$(args)" "--dangerously-skip-permissions|--add-dir|D|-i|make a page|"
check "no key: Zeltro's provider setting removed" "$(jget "$SET" modelProvider)" "None"
ZENV="ZELTRO_AI_AGENT=agy ZELTRO_AI_API_KEY= ZELTRO_AI_LANGUAGE=Spanish"
z ai --one-off "hola" >/dev/null
check "language rides on the prompt" "$(args | grep -c 'Reply to the user in Spanish')" "1"
rm -f "$T/agy-args.log"
ZENV="ZELTRO_AI_AGENT=agy ZELTRO_AI_API_BASE=https://example.invalid/v1"
z ai --one-off "x" >/dev/null
check "a custom endpoint is refused" "$([ -f "$T/agy-args.log" ] && echo ran || echo refused)" "refused"

echo "provider setting"
printf '{"modelProvider": "gemini", "colorScheme": "dark"}\n' > "$SET"
sh_ 'export GEMINI_API_KEY=k; zeltro_agy_provider; unset GEMINI_API_KEY; zeltro_agy_provider'
check "user's own provider kept (Zeltro didn't set it)" "$(jget "$SET" modelProvider) $(jget "$SET" colorScheme)" "gemini dark"
printf 'not json' > "$SET"
sh_ 'export GEMINI_API_KEY=k; zeltro_agy_provider'
check "unparseable settings untouched" "$(cat "$SET")" "not json"
rm -f "$SET"

echo "unattended"
ZENV=""
out="$(z ai-unattended --agent agy on --json-output)"
check "on: read back true" "$(field "$out" unattended)" "true"
check "toolPermission always-proceed" "$(jget "$SET" toolPermission) $(jget "$SET" artifactReviewPolicy)" "always-proceed always-proceed"
check "config_file reported" "$(field "$out" config_file)" "$SET"
out="$(z ai-unattended --agent agy off --json-output)"
check "off: read back false" "$(field "$out" unattended)" "false"
check "agy's own defaults back" "$(jget "$SET" toolPermission) $(jget "$SET" artifactReviewPolicy)" "request-review asks-for-review"
printf '{"toolPermission": "strict"}\n' > "$SET"
z ai-unattended --agent agy off --json-output >/dev/null
check "off leaves a user's own stricter setting" "$(jget "$SET" toolPermission)" "strict"
printf '{oops' > "$SET"
out="$(z ai-unattended --agent agy on --json-output)"
check "unparseable: not written" "$(cat "$SET")" "{oops"
check "unparseable: reported unknown, not success" "$(field "$out" status)" "error"
rm -f "$SET"

echo "folder trust"
mkdir -p "$T/home/projects/demo"
printf '{"colorScheme": "dark"}\n' > "$SET"
sh_ "zeltro_trust_project_for_agents '$T/home/projects/demo'; zeltro_trust_project_for_agents '$T/home/projects/demo'"
check "project trusted once" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["trustedWorkspaces"])' "$SET")" "['$(cd "$T/home/projects/demo" && pwd -P)']"
check "other settings kept" "$(jget "$SET" colorScheme)" "dark"
mkdir -p "$T/elsewhere"
sh_ "zeltro_trust_project_for_agents '$T/elsewhere'"
check "outside the projects dir: not trusted" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["trustedWorkspaces"]))' "$SET")" "1"

echo "ai-status"
ZENV=""
out="$(z ai-status --agent agy --json-output)"
check "installed, version" "$(field "$out" installed) $(field "$out" version)" "True 1.4.6"
check "not signed in" "$(field "$out" auth) $(field "$out" signed_in)" "none False"
ZENV="FAKE_AGY_SIGNED_IN=1"
out="$(z ai-status --agent agy --json-output)"
check "signed in with Google" "$(field "$out" auth) $(field "$out" signed_in) $(field "$out" account)" "subscription True Google account"
ZENV="ZELTRO_AI_AGENT=agy ZELTRO_AI_API_KEY=AIzaTEST"
check "a profile key counts as ready" "$(field "$(z ai-status --agent agy --json-output)" auth)" "api_key"
check "ai-login isn't offered" "$(field "$out" login_supported)" "False"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
