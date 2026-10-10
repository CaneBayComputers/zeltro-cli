#!/bin/bash
# zeltro rename: folder projects (created and added), a Docker project's compose,
# Claude Code's history, the in-use check, --dry-run and --github (with a fake
# gh). Runs against a scratch projects directory and a sandboxed HOME; starts no
# containers and touches no network.
#
#   bash tests/rename-project.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
Z="$REPO/src/zeltro"
T="$(mktemp -d)"
SLEEPER=""
trap '[ -n "$SLEEPER" ] && kill "$SLEEPER" 2>/dev/null; rm -rf "$T"' EXIT
export ZELTRO_TEST_PROJECTS_DIR="$T/projects"
export XDG_DATA_HOME="$T/data"
export PYTHONDONTWRITEBYTECODE=1
export HOME="$T/home"
export ZELTRO_NO_AGENT_TRUST=1
unset CLAUDE_CONFIG_DIR
mkdir -p "$ZELTRO_TEST_PROJECTS_DIR" "$T/elsewhere/tools" "$T/data" "$HOME/.claude/projects" "$T/bin"
P="$(cd "$ZELTRO_TEST_PROJECTS_DIR" && pwd -P)"
# Names nothing on a real machine uses, so the Docker clash checks find nothing.
N="zt-rn-$$"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
j() { python3 -c 'import json,sys
d=json.loads(sys.argv[1])
for k in sys.argv[2].split("."):
    d = d[int(k)] if isinstance(d, list) else d.get(k)
print(json.dumps(d) if isinstance(d,(bool,type(None),dict,list)) else d)' "$1" "$2" 2>/dev/null; }
z() { "$Z" "$@" --json-output 2>/dev/null | tail -n 1; }
enc() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'; }
rec() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$P/.zeltro/folders/$1.json" "$2" 2>/dev/null; }

echo "refusals"
z new folder "$N-a" >/dev/null
check "unknown project" "$(j "$(z rename nope-$N x)" error)" "not_found"
check "no new name" "$(j "$(z rename "$N-a")" error)" "missing_name"
check "same name" "$(j "$(z rename "$N-a" "$N-a")" error)" "same_name"
check "bad name" "$(j "$(z rename "$N-a" '!!!')" error)" "bad_name"
z new folder "$N-taken" >/dev/null
check "taken name" "$(j "$(z rename "$N-a" "$N-taken")" error)" "name_taken"
check "--github without a GitHub origin" "$(j "$(z rename "$N-a" "$N-b" --github)" error)" "github_unavailable"
check "nothing moved by a refusal" "$([ -d "$P/$N-a" ] && [ ! -e "$P/$N-b" ] && echo yes)" "yes"

echo "dry run"
out=$(z rename "$N-a" "$N-b" --dry-run)
check "preview" "$(j "$out" status)" "preview"
check "kind folder" "$(j "$out" kind)" "folder"
check "github reason" "$(j "$out" github.reason)" "no_github_remote"
check "no new name needed" "$(j "$(z rename "$N-a" --dry-run)" status)" "preview"
check "changes nothing" "$([ -d "$P/$N-a" ] && [ ! -e "$P/$N-b" ] && echo yes)" "yes"

echo "created folder project"
OLD_REAL="$P/$N-a"
mkdir -p "$HOME/.claude/projects/$(enc "$OLD_REAL")"
echo '{"cwd":"x"}' > "$HOME/.claude/projects/$(enc "$OLD_REAL")/s1.jsonl"
printf '{"projects": {"%s": {"allowedTools": ["Bash"]}}}\n' "$OLD_REAL" > "$HOME/.claude.json"
z set-metadata "$N-a" --emoji "🧪" >/dev/null
out=$(z rename "$N-a" "New Name $N")
check "succeeds" "$(j "$out" status)" "success"
check "name cleaned" "$(j "$out" project_name)" "new-name-$N"
NN="new-name-$N"
check "folder moved" "$([ -d "$P/$NN" ] && [ ! -e "$P/$N-a" ] && echo yes)" "yes"
check "record moved" "$(rec "$NN" origin)" "created"
check "record path follows" "$(rec "$NN" path)" "$P/$NN"
check "old record gone" "$([ -e "$P/.zeltro/folders/$N-a.json" ] && echo yes || echo no)" "no"
check "metadata kept" "$(j "$(z get-metadata "$NN")" metadata.emoji)" "🧪"
check "AGENTS.md retitled" "$(grep -c "^# $NN\$" "$P/$NN/AGENTS.md")" "1"
check "Claude history moved" "$(cat "$HOME/.claude/projects/$(enc "$P/$NN")/s1.jsonl" 2>/dev/null)" '{"cwd":"x"}'
check "reported" "$(j "$out" ai_history_moved)" "true"
check "Claude settings follow" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["projects"]; print(sys.argv[2] in d, sys.argv[3] in d)' "$HOME/.claude.json" "$OLD_REAL" "$P/$NN")" "False True"
st=$("$Z" status --all --json-output 2>/dev/null)
check "status lists the new name" "$(python3 -c 'import json,sys; print(sorted(p["name"] for p in json.loads(sys.argv[1])["projects"] if sys.argv[2] in p["name"]))' "$st" "$N")" "['$NN', '$N-taken']"

echo "added folder project"
echo "keep" > "$T/elsewhere/tools/f.txt"
z add "$T/elsewhere/tools" --name "$N-tools" >/dev/null
out=$(z rename "$N-tools" "$N-kit")
check "succeeds" "$(j "$out" status)" "success"
check "origin added" "$(j "$out" origin)" "added"
check "link renamed" "$([ -L "$P/$N-kit" ] && [ ! -e "$P/$N-tools" ] && echo yes)" "yes"
check "user's folder stays" "$(cat "$T/elsewhere/tools/f.txt")" "keep"
check "record path unchanged" "$(rec "$N-kit" path)" "$(cd "$T/elsewhere/tools" && pwd -P)"
check "nothing written in it" "$(ls -A "$T/elsewhere/tools" | tr '\n' ' ')" "f.txt "

echo "Docker project (compose only, nothing running)"
mkdir -p "$P/$N-web"
cat > "$P/$N-web/docker-compose.yaml" <<EOF
services:
  server:
    image: nginx:alpine
    container_name: $N-web
    x-metadata:
      emoji: "🌐"
  worker:
    image: busybox
    container_name: $N-web-worker
EOF
out=$(z rename "$N-web" "$N-site")
check "succeeds" "$(j "$out" status)" "success"
check "kind docker" "$(j "$out" kind)" "docker"
check "was not running" "$(j "$out" restarted)" "false"
check "web container renamed" "$(grep -c "container_name: $N-site\$" "$P/$N-site/docker-compose.yaml")" "1"
check "app's own container_name kept" "$(grep -c "container_name: $N-web-worker\$" "$P/$N-site/docker-compose.yaml")" "1"
check "x-metadata kept" "$(grep -c 'emoji: "🌐"' "$P/$N-site/docker-compose.yaml")" "1"

echo "in use"
# Its own process group, like a shell in another terminal (job control does that).
set -m; ( cd "$P/$N-site" && exec sleep 60 ) & SLEEPER=$!; set +m
sleep 0.3
out=$(z rename "$N-site" "$N-x")
check "refused while a process is inside" "$(j "$out" error)" "in_use"
check "names the process" "$(j "$out" in_use.0.name)" "sleep"
check "still there" "$([ -d "$P/$N-site" ] && echo yes)" "yes"
check "dry run lists it" "$(j "$(z rename "$N-site" "$N-x" --dry-run)" in_use.0.name)" "sleep"
out=$(z rename "$N-site" "$N-x" --force)
check "--force renames anyway" "$(j "$out" status)" "success"
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null; SLEEPER=""
out=$( cd "$P/$N-x" && "$Z" rename "$N-x" "$N-y" --json-output 2>/dev/null | tail -n 1 )
check "the caller's own shell inside it doesn't count" "$(j "$out" status)" "success"

echo "--github (fake gh)"
cat > "$T/bin/gh" <<'FAKE'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
    "repo view") echo "${FAKE_PERM:-ADMIN}" ;;
    "repo rename") exit 0 ;;
esac
FAKE
chmod +x "$T/bin/gh"
export GH_LOG="$T/gh.log"
git -C "$P/$N-y" init -q 2>/dev/null
git -C "$P/$N-y" remote add origin "git@github.com:someone/old-repo.git"
out=$(PATH="$T/bin:$PATH" z rename "$N-y" "$N-z" --dry-run)
check "dry run sees the repo" "$(j "$out" github.repo)" "someone/old-repo"
check "and that it can rename it" "$(j "$out" github.can_rename)" "true"
out=$(PATH="$T/bin:$PATH" FAKE_PERM=WRITE z rename "$N-y" "$N-z" --github)
check "not an admin: refused" "$(j "$out" github_reason)" "not_repo_admin"
check "refused before anything moved" "$([ -d "$P/$N-y" ] && echo yes)" "yes"
out=$(PATH="$T/bin:$PATH" z rename "$N-y" "$N-z" --github)
check "renamed" "$(j "$out" github.renamed)" "true"
check "new repo reported" "$(j "$out" github.repo)" "someone/$N-z"
check "gh asked to rename" "$(grep -c "^repo rename $N-z --repo someone/old-repo --yes" "$GH_LOG")" "1"
check "origin updated" "$(git -C "$P/$N-z" remote get-url origin)" "git@github.com:someone/$N-z.git"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
