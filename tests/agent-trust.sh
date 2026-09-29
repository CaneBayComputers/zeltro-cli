#!/bin/bash
# Test zeltro_trust_project_for_agents: new/install mark the project trusted for
# Claude Code and Codex so Create with AI's first interactive session doesn't stop
# at "Is this a project you created or one you trust?" (default: "No, exit").
# Runs against a sandboxed HOME; never touches the real ~/.claude.json.
#
#   bash tests/agent-trust.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }

mkdir -p "$T/home/.codex" "$T/projects/demo" "$T/elsewhere" "$T/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/codex"; chmod +x "$T/bin/codex"
printf '[projects."/some/other"]\ntrust_level = "trusted"\n' > "$T/home/.codex/config.toml"
echo '{"numStartups": 5, "projects": {"/x": {"allowedTools": ["a"], "hasTrustDialogAccepted": false}}}' > "$T/home/.claude.json"
chmod 600 "$T/home/.claude.json"

trust() { # <dir>: run the helper with HOME sandboxed and PROJECTS_DIR pointed at $T/projects
    ( export HOME="$T/home" PATH="$T/bin:$PATH"; unset CODEX_HOME
      set +u; source "$REPO/src/scripts/functions.sh" >/dev/null 2>&1
      get_projects_dir() { echo "$T/projects"; }
      set -e; zeltro_trust_project_for_agents "$1"; echo "__REACHED__" )
}
claude_trust() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["projects"].get(sys.argv[2],{}).get("hasTrustDialogAccepted"))' "$T/home/.claude.json" "$1"; }

DEMO="$T/projects/demo"
trust "$DEMO" | grep -q __REACHED__ && ok "returns normally" || bad "aborted"
[ "$(claude_trust "$DEMO")" = "True" ] && ok "Claude: project marked trusted" || bad "Claude: $(claude_trust "$DEMO")"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["numStartups"]==5 and d["projects"]["/x"]["allowedTools"]==["a"]' "$T/home/.claude.json" \
    && ok "Claude: other settings and projects kept" || bad "Claude: other data lost"
[ "$(stat -c %a "$T/home/.claude.json" 2>/dev/null || stat -f %Lp "$T/home/.claude.json")" = 600 ] && ok "Claude: file mode kept (600)" || bad "Claude: mode changed"
grep -qF "[projects.\"$DEMO\"]" "$T/home/.codex/config.toml" && ok "Codex: trusted entry added" || bad "Codex: no entry"
trust "$DEMO" >/dev/null
[ "$(grep -cF "[projects.\"$DEMO\"]" "$T/home/.codex/config.toml")" = 1 ] && ok "Codex: no duplicate table on a second run" || bad "Codex: duplicated"
python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$T/home/.codex/config.toml" 2>/dev/null \
    && ok "Codex: config.toml still valid TOML" || { python3 -c 'import tomllib' 2>/dev/null && bad "Codex: invalid TOML" || ok "Codex: (tomllib unavailable, skipped)"; }

trust "$T/elsewhere" >/dev/null
[ "$(claude_trust "$T/elsewhere")" = "None" ] && ! grep -qF elsewhere "$T/home/.codex/config.toml" \
    && ok "refuses a directory outside the projects folder" || bad "trusted a directory outside the projects folder"

echo '{"projects": {' > "$T/home/.claude.json"   # truncated / mid-write
trust "$DEMO" | grep -q __REACHED__ && [ "$(cat "$T/home/.claude.json")" = '{"projects": {' ] \
    && ok "unparsable ~/.claude.json left untouched" || bad "unparsable ~/.claude.json was changed"

( export HOME="$T/home" ZELTRO_NO_AGENT_TRUST=1; set +u; source "$REPO/src/scripts/functions.sh" >/dev/null 2>&1
  get_projects_dir() { echo "$T/projects"; }; mkdir -p "$T/projects/optout"; zeltro_trust_project_for_agents "$T/projects/optout" )
! grep -qF optout "$T/home/.codex/config.toml" && ok "ZELTRO_NO_AGENT_TRUST=1 skips it" || bad "opt-out ignored"

grep -q zeltro_trust_project_for_agents "$REPO/src/scripts/new_project.sh" && grep -q zeltro_trust_project_for_agents "$REPO/src/scripts/install.sh" \
    && ok "new and install call it" || bad "new/install don't call it"
! grep -q zeltro_trust_project_for_agents "$REPO/src/scripts/clone_project.sh" && ok "clone never pre-trusts (a cloned repo keeps the agent's question)" \
    || bad "clone pre-trusts"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
