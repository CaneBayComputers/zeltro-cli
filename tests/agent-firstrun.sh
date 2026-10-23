#!/bin/bash
# First-run screens: agent_firstrun.py pre-answers each agent's own keys only
# where the user hasn't answered, never replaces what it can't parse, keeps
# symlinked dotfiles symlinks; the trust helper covers Claude and Gemini; and
# Claude's unattended mode records the consent Claude Code 2.1 requires. Fake
# agents and a sandboxed HOME; no network.
#
#   bash tests/agent-firstrun.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
unset CLAUDE_CONFIG_DIR CODEX_HOME ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN NVM_DIR
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'FAKE'
#!/bin/sh
case "$*" in
    --version) echo "2.1.309 (Claude Code)" ;;
    "auth status --json") if [ "${FAKE_SIGNED_IN:-0}" = "1" ]; then echo '{"loggedIn": true}'; else echo '{"loggedIn": false}'; exit 1; fi ;;
esac
FAKE
chmod +x "$T/bin/claude"

H="$T/home"
fresh() { rm -rf "$H"; mkdir -p "$H"; }
firstrun() { # [VAR=val ...] agent
    local agent="${!#}"; local n=$(($# - 1))
    ( export HOME="$H" PATH="$T/bin:/usr/bin:/bin"; env "${@:1:$n}" python3 "$REPO/src/scripts/agent_firstrun.py" "$agent" ) >/dev/null 2>&1
}
jget() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d = d.get(k) if isinstance(d, dict) else None
print(json.dumps(d))' "$1" "$2" 2>/dev/null; }

echo "claude onboarding"
fresh; firstrun FAKE_SIGNED_IN=1 claude
check "signed in: onboarding marked done" "$(jget "$H/.claude.json" hasCompletedOnboarding)" "true"
check "with Claude's version" "$(jget "$H/.claude.json" lastOnboardingVersion)" '"2.1.309"'
check "file is private" "$(stat -c %a "$H/.claude.json" 2>/dev/null || stat -f %Lp "$H/.claude.json")" "600"
fresh; firstrun FAKE_SIGNED_IN=0 claude
check "not signed in, no key: the wizard (sign-in) stays" "$([ -e "$H/.claude.json" ] && jget "$H/.claude.json" hasCompletedOnboarding || echo untouched)" "untouched"
fresh; firstrun ANTHROPIC_API_KEY=sk-ant-api03-aaaaaaaaaa-0123456789abcdefghij claude
check "on a key: marked done" "$(jget "$H/.claude.json" hasCompletedOnboarding)" "true"
check "and the key pre-approved (last 20 chars)" "$(jget "$H/.claude.json" customApiKeyResponses.approved)" '["0123456789abcdefghij"]'
fresh; echo '{"theme": "light", "numStartups": 7, "customApiKeyResponses": {"approved": [], "rejected": ["0123456789abcdefghij"]}}' > "$H/.claude.json"
firstrun ANTHROPIC_API_KEY=sk-ant-api03-aaaaaaaaaa-0123456789abcdefghij claude
check "user's own keys kept" "$(jget "$H/.claude.json" theme) $(jget "$H/.claude.json" numStartups)" '"light" 7'
check "a key the user rejected stays rejected" "$(jget "$H/.claude.json" customApiKeyResponses.approved)" "[]"
fresh; printf '{"broken": ' > "$H/.claude.json"; firstrun FAKE_SIGNED_IN=1 claude
check "unparseable file left alone" "$(cat "$H/.claude.json")" '{"broken": '
fresh; mkdir -p "$T/ccd"; firstrun CLAUDE_CONFIG_DIR="$T/ccd" FAKE_SIGNED_IN=1 claude
check "CLAUDE_CONFIG_DIR's .claude.json" "$(jget "$T/ccd/.claude.json" hasCompletedOnboarding) $([ -e "$H/.claude.json" ] && echo home || echo none)" "true none"
fresh; echo '{"a": 1}' > "$T/dotfile.json"; ln -s "$T/dotfile.json" "$H/.claude.json"; firstrun FAKE_SIGNED_IN=1 claude
check "a symlinked .claude.json stays a symlink" "$([ -L "$H/.claude.json" ] && echo link) $(jget "$T/dotfile.json" hasCompletedOnboarding)" "link true"

echo "codex"
fresh; firstrun codex
check "no config: update picker off" "$(grep -c '^check_for_update_on_startup = false' "$H/.codex/config.toml")" "1"
fresh; mkdir -p "$H/.codex"; printf 'model = "gpt-5.5"\n\n[projects."/x"]\ntrust_level = "trusted"\n' > "$H/.codex/config.toml"; firstrun codex
check "inserted above the first table" "$(python3 -c 'import tomllib,sys; d=tomllib.load(open(sys.argv[1],"rb")); print(d["check_for_update_on_startup"], d["model"], d["projects"]["/x"]["trust_level"])' "$H/.codex/config.toml" 2>&1)" "False gpt-5.5 trusted"
firstrun codex
check "idempotent" "$(grep -c 'check_for_update_on_startup' "$H/.codex/config.toml")" "1"
fresh; mkdir -p "$H/.codex"; printf 'check_for_update_on_startup = true\n' > "$H/.codex/config.toml"; firstrun codex
check "the user's own choice kept" "$(cat "$H/.codex/config.toml")" "check_for_update_on_startup = true"
fresh; mkdir -p "$H/.codex" "$T/managed"; printf 'model = "m"\n' > "$H/.codex/config.toml"; ln -sf "$H/.codex/config.toml" "$T/managed/config.toml"
firstrun CODEX_HOME="$T/managed" codex
check "managed CODEX_HOME: the link stays, the user's file gets it" "$([ -L "$T/managed/config.toml" ] && echo link) $(grep -c check_for_update "$H/.codex/config.toml")" "link 1"

echo "gemini"
fresh; firstrun gemini
check "auth type preselected" "$(jget "$H/.gemini/settings.json" security.auth.selectedType)" '"gemini-api-key"'
fresh; mkdir -p "$H/.gemini"; echo '{"security": {"auth": {"selectedType": "oauth-personal"}}, "ui": {"theme": "x"}}' > "$H/.gemini/settings.json"; firstrun gemini
check "the user's choice kept" "$(jget "$H/.gemini/settings.json" security.auth.selectedType) $(jget "$H/.gemini/settings.json" ui.theme)" '"oauth-personal" "x"'

echo "aider"
fresh; firstrun aider
check "all five answers" "$(grep -cE '^(gitignore: false|show-release-notes: false|show-model-warnings: false|check-update: false|analytics-disable: true)$' "$H/.aider.conf.yml")" "5"
fresh; printf 'model: openai/x\ncheck-update: true' > "$H/.aider.conf.yml"; firstrun aider
check "the user's own value kept" "$(grep -c '^check-update: true$' "$H/.aider.conf.yml") $(grep -c '^check-update' "$H/.aider.conf.yml")" "1 1"
check "appended after their last line" "$(sed -n 2,3p "$H/.aider.conf.yml" | tr '\n' '|')" "check-update: true|gitignore: false|"

echo "hermes"
cat > "$T/bin/hermes" <<FAKE
#!/bin/sh
echo "\$*" >> "$T/hermes.log"
FAKE
chmod +x "$T/bin/hermes"
fresh; rm -f "$T/hermes.log"; firstrun hermes
check "no config (never set up, or a throwaway HOME): hermes not started" "$([ -e "$T/hermes.log" ] && echo started || echo no)" "no"
mkdir -p "$H/.hermes"; printf 'telemetry:\n  shared_metrics:\n    enabled: false\n' > "$H/.hermes/config.yaml"; firstrun hermes
check "not asked yet: recorded through hermes's own setter" "$(cat "$T/hermes.log" 2>/dev/null)" "config set telemetry.shared_metrics.offer_version 2"
rm -f "$T/hermes.log"; printf 'telemetry:\n  shared_metrics:\n    enabled: true\n    offer_version: 2\n' > "$H/.hermes/config.yaml"; firstrun hermes
check "already answered: left alone" "$([ -e "$T/hermes.log" ] && echo started || echo no)" "no"
printf 'telemetry:\n  shared_metrics:\n    offer_version: 1\n' > "$H/.hermes/config.yaml"; firstrun hermes
check "an older answer: asked-again marker raised" "$(cat "$T/hermes.log" 2>/dev/null)" "config set telemetry.shared_metrics.offer_version 2"
rm -f "$T/bin/hermes"

echo "zeltro_agent_firstrun (shell)"
fresh; mkdir -p "$T/proj"; git -C "$T/proj" init -q
( export HOME="$H" PATH="$T/bin:/usr/bin:/bin"; cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1; cd "$T/proj" && zeltro_agent_firstrun aider )
check "aider: .aider* hidden in .git/info/exclude" "$(grep -cx '/.aider\*' "$T/proj/.git/info/exclude")" "1"
check "aider: answers written" "$(grep -c 'gitignore: false' "$H/.aider.conf.yml")" "1"
fresh; ( export HOME="$H" PATH="$T/bin:/usr/bin:/bin" ZELTRO_NO_AGENT_FIRSTRUN=1; cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1; zeltro_agent_firstrun aider )
check "ZELTRO_NO_AGENT_FIRSTRUN=1 skips it" "$([ -e "$H/.aider.conf.yml" ] && echo written || echo none)" "none"

echo "trust"
fresh; mkdir -p "$H/projects/shop"
trust() { ( export HOME="$H" PATH="$T/bin:/usr/bin:/bin"; cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1
    get_projects_dir() { echo "$H/projects"; }; zeltro_trust_project_for_agents "$H/projects/shop" ) >/dev/null 2>&1; }
trust
P="$(cd "$H/projects/shop" && pwd -P)"
check "claude installed, no .claude.json yet: created with the trust" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["projects"][sys.argv[2]]["hasTrustDialogAccepted"])' "$H/.claude.json" "$P" 2>&1)" "True"
check "gemini not installed: no ~/.gemini made" "$([ -e "$H/.gemini" ] && echo made || echo none)" "none"
printf '#!/bin/sh\n' > "$T/bin/gemini"; chmod +x "$T/bin/gemini"; trust; rm -f "$T/bin/gemini"
check "gemini installed: folder trusted" "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2])))' "$H/.gemini/trustedFolders.json" "$P" 2>&1)" '"TRUST_FOLDER"'

echo "claude unattended consent"
fresh
z() { ( export HOME="$H" PATH="$T/bin:/usr/bin:/bin" NO_COLOR=1; "$REPO/src/zeltro" "$@" 2>/dev/null </dev/null | tail -n 1 ); }
field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
check "on" "$(field "$(z ai-unattended --agent claude on --json-output)" unattended)" "true"
check "settings record the consent" "$(jget "$H/.claude/settings.json" skipDangerousModePermissionPrompt) $(jget "$H/.claude/settings.json" permissions.defaultMode)" 'true "bypassPermissions"'
check "no auto-mode offer on start" "$(jget "$H/.claude.json" hasSeenAutoDefaultNudge)" "true"
echo '{"permissions": {"defaultMode": "bypassPermissions"}}' > "$H/.claude/settings.json"
check "bypass without the consent reads false (Claude downgrades it)" "$(field "$(z ai-unattended --agent claude status --json-output)" unattended)" "false"
echo '{"bypassPermissionsModeAccepted": true}' > "$H/.claude.json"
check "older consent in the global config counts" "$(field "$(z ai-unattended --agent claude status --json-output)" unattended)" "true"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
