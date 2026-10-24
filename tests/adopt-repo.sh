#!/bin/bash
# Adopting someone else's repo (zeltro clone / zeltro setup) without leaving
# Zeltro's files in it, and with the address the app needs.
#
# 2026-10-22, cloning a Lovable app (TanStack Start on Vite 8, bun.lock, a
# tracked AGENTS.md, two-way synced with the user's Lovable project): the fold's
# compose published no port, so `zeltro status` found no address; `zeltro setup`
# then ran `npm run dev`, which served Lovable's forced port 8080 behind nginx's
# 3000 (502); and setup edited the tracked .gitignore, which syncs into Lovable.
#
# Pure functions against throwaway dirs; no containers, no real config touched.
# Needs /etc/zeltro-cli/.env (functions.sh loads it).
#
#   bash tests/adopt-repo.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

# Run shell code with functions.sh loaded, in directory $1.
in_fn() { # <dir> <code>
    ( cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1
      cd "$1" && eval "$2" )
}
gitq() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" > /dev/null 2>&1; }

echo "Vite dev command"
vite_cmd() { # <dev script>
    mkdir -p "$T/v"; printf '{"scripts":{"dev":"%s"}}' "$1" > "$T/v/package.json"
    in_fn "$T/v" 'zeltro_vite_dev_command || echo "(npm run dev)"'
}
check "Lovable's plain 'vite dev'" "$(vite_cmd 'vite dev')" "npx vite dev --host 0.0.0.0 --port 3000 --strictPort"
check "other port and bare --host dropped, other flags kept" "$(vite_cmd 'vite --port 8080 --host --mode staging')" "npx vite --mode staging --host 0.0.0.0 --port 3000 --strictPort"
check "= forms and strictPort dropped" "$(vite_cmd 'vite --host=::1 --port=5173 --strictPort')" "npx vite --host 0.0.0.0 --port 3000 --strictPort"
check "Zeltro scaffold (already 3000) kept" "$(vite_cmd 'vite --port 3000')" "(npm run dev)"
check "shell syntax kept" "$(vite_cmd 'vite build && vite')" "(npm run dev)"
check "not vite" "$(vite_cmd 'next dev')" "(npm run dev)"
rm -f "$T/v/package.json"
check "no package.json" "$(in_fn "$T/v" 'zeltro_vite_dev_command || echo none')" "none"
mkdir -p "$T/v"; printf '{"scripts":{"dev":"vite dev"}}' > "$T/v/package.json"
check "react framework uses it" "$(in_fn "$T/v" "source '$REPO/src/frameworks/react.sh'; framework_node_start_command")" "npx vite dev --host 0.0.0.0 --port 3000 --strictPort"
check "node framework uses it" "$(in_fn "$T/v" "source '$REPO/src/frameworks/node.sh'; framework_node_start_command")" "npx vite dev --host 0.0.0.0 --port 3000 --strictPort"
printf '{"scripts":{"start":"node index.js"}}' > "$T/v/package.json"
check "node framework default unchanged" "$(in_fn "$T/v" "source '$REPO/src/frameworks/node.sh'; framework_node_start_command")" "node server.js"

echo "git exclude"
R="$T/repo"; mkdir -p "$R"; gitq -C "$R" init
printf 'node_modules\n' > "$R/.gitignore"; echo x > "$R/AGENTS.md"; gitq -C "$R" add -A; gitq -C "$R" commit -m init
touch "$R/docker-compose.yaml" "$R/package-lock.json"
in_fn "$R" 'zeltro_git_exclude "$PWD" docker-compose.yaml package-lock.json AGENTS.md; zeltro_git_exclude "$PWD" docker-compose.yaml'
check "untracked Zeltro files hidden" "$(git -C "$R" status --porcelain)" ""
check "tracked file not listed" "$(grep -c '^/AGENTS.md$' "$R/.git/info/exclude")" "0"
check "idempotent" "$(grep -c '^/docker-compose.yaml$' "$R/.git/info/exclude")" "1"
check ".gitignore untouched" "$(cat "$R/.gitignore")" "node_modules"
H="$T/home"; mkdir -p "$H/projects/plain"; gitq -C "$H" init
in_fn "$H/projects/plain" 'zeltro_git_exclude "$PWD" docker-compose.yaml'
check "folder inside another repo: that repo untouched" "$(grep -c docker-compose "$H/.git/info/exclude")" "0"
check "repo root detected" "$(in_fn "$R" 'zeltro_is_repo_root "$PWD" && echo y || echo n')" "y"
check "subfolder of a repo is not a root" "$(in_fn "$H/projects/plain" 'zeltro_is_repo_root "$PWD" && echo y || echo n')" "n"

echo "published port"
C="$T/c"; mkdir -p "$C"
cat > "$C/docker-compose.yaml" << 'EOF'
services:
  server:
    image: canebaycomputers/cbc:nginx-node
    container_name: lend-app
    networks:
      default:
        ipv4_address: 10.0.0.143
networks:
  default:
    external: true
    name: zeltro-cli_vpc
EOF
in_fn "$C" 'zeltro_compose_publish_port docker-compose.yaml lend-app 143'
check "port added to the web service" "$(python3 -c 'import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))["services"]["server"]["ports"])' "$C/docker-compose.yaml")" "['143:80']"
check "the address helpers read it" "$(grep -E "^[[:space:]]*-[[:space:]]*[\"']?[0-9]+:[0-9]+" "$C/docker-compose.yaml" | head -1 | sed 's/[^0-9]*\([0-9]*\):.*/\1/')" "143"
check "compose still valid YAML with the IP" "$(python3 -c 'import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))["services"]["server"]["networks"]["default"]["ipv4_address"])' "$C/docker-compose.yaml")" "10.0.0.143"
sed -i 's/143:80/150:80/' "$C/docker-compose.yaml"
check "an existing mapping is left alone" "$(grep -cE '150:80' "$C/docker-compose.yaml")" "1"
printf 'services:\n  web:\n    image: x\n' > "$C/docker-compose.yaml"
check "no service with that name: reports failure" "$(in_fn "$C" 'zeltro_compose_publish_port docker-compose.yaml lend-app 143 && echo 0 || echo 1')" "1"

echo "project AGENTS.md"
P="$T/proj"; mkdir -p "$P"; gitq -C "$P" init; echo "Lovable's notes" > "$P/AGENTS.md"; gitq -C "$P" add -A; gitq -C "$P" commit -m init
in_fn "$P" 'write_project_agents_md proj "$PWD" > /dev/null 2>&1; echo "$ZELTRO_AGENTS_FILE"' > "$T/out"
check "tracked AGENTS.md: context goes to ZELTRO.md" "$(cat "$T/out")" "ZELTRO.md"
check "tracked AGENTS.md untouched" "$(cat "$P/AGENTS.md")" "Lovable's notes"
check "ZELTRO.md has the context" "$(grep -c 'BEGIN ZELTRO CONTEXT' "$P/ZELTRO.md" 2>/dev/null)" "1"
check "nothing shows in git status" "$(git -C "$P" status --porcelain)" ""
Q="$T/proj2"; mkdir -p "$Q"; gitq -C "$Q" init
check "no tracked AGENTS.md: AGENTS.md as before" "$(in_fn "$Q" 'write_project_agents_md proj2 "$PWD" > /dev/null 2>&1; echo "$ZELTRO_AGENTS_FILE"')" "AGENTS.md"
check "and written" "$(grep -c 'BEGIN ZELTRO CONTEXT' "$Q/AGENTS.md" 2>/dev/null)" "1"

echo "AGENTS.md without a session (--one-off, the GUI)"
# 2026-10-24: a Laravel 13 project made from the GUI had only Laravel's own
# AGENTS.md ("install PHP from php.new"), and Codex installed PHP on the host.
L="$T/projects/lara"; mkdir -p "$L"; printf '# Laravel\n\nInstall PHP from php.new.\n' > "$L/AGENTS.md"
in_fn "$L" 'PROJECTS_DIR_PATH="$(dirname "$PWD")" SKIP_INTERACTIVE=1 JSON_OUTPUT=1 ai_handoff lara; echo "rc=$?"' > "$T/out" 2>&1
check "returns, starts nothing, prints nothing" "$(cat "$T/out")" "rc=0"
check "Zeltro block written first" "$(head -n 1 "$L/AGENTS.md")" "<!-- BEGIN ZELTRO CONTEXT -->"
check "the framework's text kept" "$(grep -c 'Install PHP from php.new' "$L/AGENTS.md")" "1"
check "says it overrides host installs" "$(grep -c 'This overrides' "$L/AGENTS.md")" "1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
