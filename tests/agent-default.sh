#!/bin/bash
# Agents installed in per-user bin directories are found from a non-login shell
# (ssh), and a blank AI_AGENT falls back to the first installed agent.
#
# 2026-10-21: on a fresh install env.example leaves AI_AGENT blank, so the app's
# "Host default" said no agent was configured. And over ssh (no login PATH),
# `ai-set --json-output` reported installed_agents ["codex"] although Claude was
# in ~/.local/bin, where its native installer puts it.
#
# Uses a throwaway HOME with stub agents and PATH=/usr/bin:/bin; touches no real
# config. Needs /etc/zeltro-cli/.env (functions.sh loads it).
#
#   bash tests/agent-default.sh
set -u
# The sandboxed HOMEs carry their own ~/.nvm; an NVM_DIR from the caller would win.
unset NVM_DIR

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

stub() { # <dir> <agent>...
    local d="$1"; shift
    mkdir -p "$d"
    for a in "$@"; do printf '#!/bin/sh\necho "%s stub"\n' "$a" > "$d/$a"; chmod +x "$d/$a"; done
}

# Source functions.sh the way a non-login ssh shell would see things, then run
# the given shell code. $1 = HOME.
in_shell() { # <home> <code>
    ( export HOME="$1" PATH=/usr/bin:/bin NO_COLOR=1
      unset NPM_CONFIG_PREFIX npm_config_prefix ZELTRO_AI_AGENT
      cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1
      eval "$2" )
}

echo "per-user bin directories reach PATH"
H="$T/h1"; stub "$H/.local/bin" claude; stub "$H/.npm-global/bin" gemini; stub "$H/.bun/bin" qwen
check "claude in ~/.local/bin" "$(in_shell "$H" 'command -v claude')" "$H/.local/bin/claude"
check "gemini in ~/.npm-global/bin" "$(in_shell "$H" 'command -v gemini')" "$H/.npm-global/bin/gemini"
check "qwen in ~/.bun/bin" "$(in_shell "$H" 'command -v qwen')" "$H/.bun/bin/qwen"
check "appended after system dirs" "$(in_shell "$H" 'echo "${PATH%%:*}"')" "/usr/bin"
check "no duplicates on re-source" "$(in_shell "$H" 'source scripts/functions.sh >/dev/null 2>&1; tr : "\n" <<<"$PATH" | grep -c "/.local/bin$"')" "1"

H="$T/h2"; stub "$H/npmg/bin" codex; printf 'prefix=~/npmg\n' > "$H/.npmrc"
check "npm prefix from ~/.npmrc" "$(in_shell "$H" 'command -v codex')" "$H/npmg/bin/codex"

H="$T/h3"; stub "$H/.nvm/versions/node/v20.19.3/bin" opencode; stub "$H/.nvm/versions/node/v22.23.3/bin" gemini
mkdir -p "$H/.nvm/alias"; echo 20 > "$H/.nvm/alias/default"
check "nvm default alias wins over newest" "$(in_shell "$H" 'command -v opencode')" "$H/.nvm/versions/node/v20.19.3/bin/opencode"
rm "$H/.nvm/alias/default"
check "nvm without alias: newest" "$(in_shell "$H" 'command -v gemini')" "$H/.nvm/versions/node/v22.23.3/bin/gemini"

echo "blank AI_AGENT picks the first installed agent"
H="$T/h4"; stub "$H/.local/bin" codex aider claude
check "claude before codex and aider" "$(in_shell "$H" 'AI_AGENT=; zeltro_fill_default_agent; echo "$AI_AGENT $ZELTRO_AI_AGENT_AUTO"')" "claude 1"
H="$T/h5"; stub "$H/.local/bin" aider codex
check "codex before aider" "$(in_shell "$H" 'AI_AGENT=; zeltro_fill_default_agent; echo "$AI_AGENT"')" "codex"
check "a configured agent is kept" "$(in_shell "$H" 'AI_AGENT=gemini; zeltro_fill_default_agent; echo "$AI_AGENT $ZELTRO_AI_AGENT_AUTO"')" "gemini 0"
H="$T/h6"; mkdir -p "$H"
check "nothing installed: stays blank" "$(in_shell "$H" 'AI_AGENT=; zeltro_fill_default_agent; echo "[$AI_AGENT] $ZELTRO_AI_AGENT_AUTO"')" "[] 0"

echo "saving the pick"
H="$T/h5"; E="$T/env"
printf 'PROJECTS_DIR="/x"\nAI_AGENT=\nAI_MODEL=\n' > "$E"
in_shell "$H" "AI_AGENT=; zeltro_fill_default_agent save '$E'" >/dev/null
check "AI_AGENT line replaced" "$(grep '^AI_AGENT=' "$E")" 'AI_AGENT="codex"'
check "other lines kept" "$(sed -n '1p;3p' "$E" | tr '\n' ' ')" 'PROJECTS_DIR="/x" AI_MODEL= '
printf 'PROJECTS_DIR="/x"\n' > "$E"
in_shell "$H" "AI_AGENT=; zeltro_fill_default_agent save '$E'" >/dev/null
check "missing key appended" "$(grep '^AI_AGENT=' "$E")" 'AI_AGENT="codex"'
# Root-owned in real life: written with `sudo -n` when that needs no password
# (this box may allow it), else left alone. Either way it must not prompt.
printf 'AI_AGENT=\n' > "$E"; chmod 444 "$E"
check "unwritable file: still picked, no prompt" "$(in_shell "$H" "AI_AGENT=; zeltro_fill_default_agent save '$E' </dev/null; echo \$AI_AGENT")" "codex"
rm -f "$E"; printf 'AI_AGENT=\n' > "$E"
in_shell "$H" "AI_AGENT=; zeltro_fill_default_agent '$E'" >/dev/null
check "without save: file untouched" "$(cat "$E")" "AI_AGENT="

echo "ai-set --json-output over a non-login PATH"
H="$T/h1"
json=$( export HOME="$H" PATH=/usr/bin:/bin NO_COLOR=1; "$REPO/src/zeltro" ai-set --json-output 2>/dev/null </dev/null | tail -n 1 )
check "valid JSON with agent_auto" "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(type(d["agent_auto"]).__name__)' "$json" 2>&1)" "bool"
check "installed_agents sees ~/.local/bin etc." "$(python3 -c 'import json,sys; print(" ".join(sorted(json.loads(sys.argv[1])["installed_agents"])))' "$json" 2>&1)" "claude gemini qwen"

echo "ai-install on a fresh account (no ~/.local/bin yet)"
# A fake curl whose "installer" creates ~/.local/bin/<agent> and prints the
# native installers' PATH advice.
H="$T/fresh"; mkdir -p "$H" "$T/fakebin"
cat > "$T/fakebin/curl" <<'FAKE'
#!/bin/sh
case "$*" in *claude.ai*) a=claude ;; *aider*) a=aider ;; *) exit 22 ;; esac
cat <<EOS
mkdir -p "\$HOME/.local/bin"
printf '#!/bin/sh\necho "2.1.309 (Claude Code)"\n' > "\$HOME/.local/bin/$a"; chmod +x "\$HOME/.local/bin/$a"
echo "Installing $a ..."
echo "⚠ Setup notes:"
echo "  • Native installation exists but ~/.local/bin is not in your PATH. Run:"
echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc then open a new terminal or run: source ~/.bashrc"
echo "warning: \$HOME/.local/bin is not on your PATH. To use installed tools, run export PATH=\"\$HOME/.local/bin:\$PATH\""
echo "✅ Installation complete!"
EOS
FAKE
chmod +x "$T/fakebin/curl"
for a in claude aider; do
    rm -rf "$H/.local"
    err="$T/install-$a.err"
    json=$( export HOME="$H" PATH="$T/fakebin:/usr/bin:/bin" NO_COLOR=1; "$REPO/src/zeltro" ai-install --agent "$a" --json-output 2>"$err" </dev/null | tail -n 1 )
    check "$a: installed, found right after" "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["status"], d["installed"])' "$json" 2>&1)" "success True"
    check "$a: installer output still shown" "$(grep -c 'Installation complete' "$err")" "1"
    check "$a: PATH advice filtered" "$(grep -cE 'not (in|on) your PATH|Setup notes|export PATH' "$err")" "0"
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
