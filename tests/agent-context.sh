#!/bin/bash
# `zeltro ai` and `zeltro resume` refresh the project's Zeltro context
# (AGENTS.md, or ZELTRO.md in a repo that tracks its own AGENTS.md) and point
# agents that don't read AGENTS.md themselves at it. The GUI starts every
# session through these two commands, so this is how a project made with
# --one-off, or before the block existed, gets its context.
#
# 2026-10-24, GUI on Windows/WSL: a Laravel 13 project had only Laravel's own
# AGENTS.md ("install PHP from php.new") and Codex installed PHP on the host.
#
# Fake agents and docker on PATH, a sandboxed HOME and a scratch projects
# directory; no network, no containers.
#
#   bash tests/agent-context.sh
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

# Each fake agent logs its arguments, one per line. docker reports every
# container running, so resume doesn't try to start anything.
mkdir -p "$T/bin" "$T/home" "$T/projects"
for a in claude codex aider agy; do
    cat > "$T/bin/$a" <<FAKE
#!/bin/bash
case "\$1" in --version) echo "1.0.0"; exit 0 ;; auth) echo '{"loggedIn": true}'; exit 0 ;; models) exit 0 ;; esac
printf '%s\n' "\$@" > "$T/args.log"
FAKE
done
printf '#!/bin/bash\n[ "$1 $2" = "container inspect" ] && echo true\nexit 0\n' > "$T/bin/docker"
chmod +x "$T/bin/"*
P="$(cd "$T/projects" && pwd -P)"

z() { # <cwd> <zeltro args...>, with ZENV assignments
    local cwd="$1"; shift
    ( cd "$cwd" && export HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" NO_COLOR=1 ZELTRO_TEST_PROJECTS_DIR="$P" \
          ZELTRO_NO_AGENT_TRUST=1 ZELTRO_AI_MODEL= ZELTRO_AI_API_KEY= ZELTRO_AI_API_BASE= ZELTRO_AI_LANGUAGE=
      env ${ZENV:-} "$REPO/src/zeltro" "$@" >/dev/null 2>&1 </dev/null )
}
args() { tr '\n' '|' < "$T/args.log" 2>/dev/null; }
gitq() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" > /dev/null 2>&1; }
newproj() { # <name>: a Laravel-shaped project with the framework's own AGENTS.md
    mkdir -p "$P/$1/app"
    printf 'services:\n  %s:\n    image: x\n    ports:\n      - "151:80"\n    networks:\n      default:\n        ipv4_address: 10.9.9.151\n' "$1" > "$P/$1/docker-compose.yaml"
    printf '# Laravel\n\nInstall PHP from php.new.\n' > "$P/$1/AGENTS.md"
}

echo "zeltro ai, Claude (reads only CLAUDE.md)"
newproj lara
rm -f "$T/args.log"
ZENV="ZELTRO_AI_AGENT=claude" z "$P/lara/app" ai "make a page"
check "block written into the framework's AGENTS.md" "$(head -n 1 "$P/lara/AGENTS.md")" "<!-- BEGIN ZELTRO CONTEXT -->"
check "the framework's text kept" "$(grep -c 'Install PHP from php.new' "$P/lara/AGENTS.md")" "1"
check "pointer on --append-system-prompt, from a subfolder" "$(args | grep -c -- "--append-system-prompt|This is a Zeltro project. Before anything else, read $P/lara/AGENTS.md")" "1"
check "the prompt itself unchanged" "$(args | grep -c '|make a page|$')" "1"
m1="$(stat -c %Y "$P/lara/AGENTS.md" 2>/dev/null || stat -f %m "$P/lara/AGENTS.md")"
touch -d '-1 hour' "$P/lara/AGENTS.md" 2>/dev/null || touch -t "$(date -v-1H +%Y%m%d%H%M)" "$P/lara/AGENTS.md"
m2="$(stat -c %Y "$P/lara/AGENTS.md" 2>/dev/null || stat -f %m "$P/lara/AGENTS.md")"
ZENV="ZELTRO_AI_AGENT=claude" z "$P/lara" ai "again"
check "unchanged context: file not rewritten" "$(stat -c %Y "$P/lara/AGENTS.md" 2>/dev/null || stat -f %m "$P/lara/AGENTS.md")" "$m2"
[ "$m1" != "$m2" ] || bad "mtime setup"

echo "zeltro ai, language too"
ZENV="ZELTRO_AI_AGENT=claude ZELTRO_AI_LANGUAGE=Spanish" z "$P/lara" ai "hola"
check "one system prompt: pointer, then language" "$(args | grep -c "follow that block. Reply to the user in Spanish")" "1"

echo "zeltro ai, Codex (reads AGENTS.md itself)"
ZENV="ZELTRO_AI_AGENT=codex" z "$P/lara" ai "make a page"
check "no developer_instructions" "$(args | grep -c developer_instructions)" "0"

echo "repo that tracks its own AGENTS.md: ZELTRO.md"
newproj lov
gitq -C "$P/lov" init; gitq -C "$P/lov" add AGENTS.md; gitq -C "$P/lov" commit -m init
ZENV="ZELTRO_AI_AGENT=codex" z "$P/lov" ai "make a page"
check "tracked AGENTS.md untouched" "$(head -n 1 "$P/lov/AGENTS.md")" "# Laravel"
check "ZELTRO.md written" "$(grep -c 'BEGIN ZELTRO CONTEXT' "$P/lov/ZELTRO.md" 2>/dev/null)" "1"
check "Codex pointed at ZELTRO.md, then the repo's AGENTS.md" "$(args | grep -c "developer_instructions=\"This is a Zeltro project. Before anything else, read $P/lov/ZELTRO.md (how to work in this project with Zeltro), then the repo's own AGENTS.md")" "1"

echo "aider and agy"
ZENV="ZELTRO_AI_AGENT=aider" z "$P/lara" ai "make a page"
check "aider: --read the context file" "$(args | grep -c -- "--read|$P/lara/AGENTS.md|")" "1"
ZENV="ZELTRO_AI_AGENT=agy" z "$P/lara" ai "make a page"
check "agy: pointer rides on the prompt" "$(args | grep -c "This is a Zeltro project")" "1"

echo "outside a project"
mkdir -p "$T/elsewhere"
ZENV="ZELTRO_AI_AGENT=claude" z "$T/elsewhere" ai "hi"
check "no pointer, nothing written" "$(args | grep -c 'Zeltro project')$(ls "$T/elsewhere" | wc -l | tr -d ' ')" "00"

echo "zeltro resume"
newproj old
rm -f "$T/args.log"
ZENV="ZELTRO_AI_AGENT=claude" z "$T" resume old
check "block written on resume" "$(grep -c 'BEGIN ZELTRO CONTEXT' "$P/old/AGENTS.md")" "1"
check "resumed with the pointer" "$(args | grep -c -- "--continue|--append-system-prompt|This is a Zeltro project. Before anything else, read $P/old/AGENTS.md")" "1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
