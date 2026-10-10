#!/bin/bash
# Folder projects: `zeltro new folder`, `zeltro add`, and how status, metadata,
# up/down/disable, remove and the agent bus treat them. Also the classifier's
# folder candidate. Runs against a scratch projects directory
# (ZELTRO_TEST_PROJECTS_DIR); starts no containers and calls no AI.
#
#   bash tests/folder-projects.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
Z="$REPO/src/zeltro"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export ZELTRO_TEST_PROJECTS_DIR="$T/projects"
export XDG_DATA_HOME="$T/data"
mkdir -p "$ZELTRO_TEST_PROJECTS_DIR" "$T/elsewhere/my-scripts" "$T/data"
P="$ZELTRO_TEST_PROJECTS_DIR"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
j() { python3 -c 'import json,sys
d=json.loads(sys.argv[1])
for k in sys.argv[2].split("."):
    d = d[int(k)] if isinstance(d, list) else d.get(k)
print(json.dumps(d) if isinstance(d,(bool,type(None),dict,list)) else d)' "$1" "$2" 2>/dev/null; }
proj() { # <status json> <name> <field>: one field of one project
    python3 -c 'import json,sys
d=json.loads(sys.argv[1])
p=[x for x in d["projects"] if x["name"]==sys.argv[2]]
v=p[0].get(sys.argv[3]) if p else "ABSENT"
print(json.dumps(v) if isinstance(v,(bool,type(None),dict,list)) else v)' "$1" "$2" "$3" 2>/dev/null; }
z() { "$Z" "$@" --json-output 2>/dev/null | tail -n 1; }

echo "zeltro new folder"
out=$(z new folder "Photo Renamer")
check "succeeds" "$(j "$out" status)" "success"
check "kind folder" "$(j "$out" kind)" "folder"
check "origin created" "$(j "$out" origin)" "created"
check "name cleaned" "$(j "$out" project_name)" "photo-renamer"
check "folder exists" "$([ -d "$P/photo-renamer" ] && echo yes)" "yes"
check "AGENTS.md says folder project" "$(grep -c 'Zeltro folder project' "$P/photo-renamer/AGENTS.md")" "1"
check "no compose file" "$([ -e "$P/photo-renamer/docker-compose.yaml" ] && echo yes || echo no)" "no"
check "git repo" "$([ -d "$P/photo-renamer/.git" ] && echo yes || echo no)" "$(command -v git >/dev/null && echo yes || echo no)"
out=$(z new folder photo-renamer)
check "same name refused" "$(j "$out" error)" "name_taken"

echo "zeltro add"
echo "print('hi')" > "$T/elsewhere/my-scripts/run.py"
before=$(cd "$T/elsewhere/my-scripts" && ls -A | sort | tr '\n' ' ')
out=$(z add "$T/elsewhere/my-scripts")
check "succeeds" "$(j "$out" status)" "success"
check "origin added" "$(j "$out" origin)" "added"
check "name from folder" "$(j "$out" project_name)" "my-scripts"
check "path is the real folder" "$(j "$out" path)" "$(cd "$T/elsewhere/my-scripts" && pwd -P)"
check "project is a symlink" "$([ -L "$P/my-scripts" ] && echo yes)" "yes"
check "nothing written inside the folder" "$(cd "$T/elsewhere/my-scripts" && ls -A | sort | tr '\n' ' ')" "$before"
out=$(z add "$T/elsewhere/my-scripts")
check "same path again refused" "$(j "$out" error)" "already_added"
check "and names the project" "$(j "$out" project_name)" "my-scripts"
mkdir -p "$T/other/my-scripts"
out=$(z add "$T/other/my-scripts")
check "name clash gets a suffix" "$(j "$out" project_name)" "my-scripts-2"
mkdir -p "$T/third"
out=$(z add "$T/third" --name my-scripts)
check "explicit --name clash refused" "$(j "$out" error)" "name_taken"
out=$(z add "$P/photo-renamer")
check "inside projects dir refused" "$(j "$out" error)" "inside_projects_dir"
out=$(z add "$HOME")
check "home folder refused" "$(j "$out" error)" "path_not_allowed"
out=$(z add "$T/nope")
check "missing path refused" "$(j "$out" error)" "not_found"
out=$(z add "$T/elsewhere/my-scripts/run.py")
check "a file refused" "$(j "$out" error)" "not_a_folder"

echo "status"
mkdir -p "$P/a-docker-app"
printf 'services:\n  a-docker-app:\n    container_name: a-docker-app\n' > "$P/a-docker-app/docker-compose.yaml"
st=$("$Z" status --all --json-output 2>/dev/null)
check "folder listed with kind" "$(proj "$st" photo-renamer kind)" "folder"
check "added folder listed" "$(proj "$st" my-scripts origin)" "added"
check "path reported" "$(proj "$st" my-scripts path)" "$(cd "$T/elsewhere/my-scripts" && pwd -P)"
check "no url" "$(proj "$st" photo-renamer local_url)" "null"
check "not running" "$(proj "$st" photo-renamer docker_running)" "false"
check "not missing" "$(proj "$st" my-scripts missing)" "false"
check "docker project says kind docker" "$(proj "$st" a-docker-app kind)" "docker"
st=$("$Z" status --json-output 2>/dev/null)
check "running-only view leaves folders out" "$(proj "$st" photo-renamer kind)" "ABSENT"

echo "metadata"
out=$(z set-metadata photo-renamer --emoji "📷" --name "Photo renamer" --description "Renames photos by date")
check "set succeeds" "$(j "$out" status)" "success"
check "display name" "$(j "$out" metadata.display_name)" "Photo renamer"
printf 'rename by EXIF date\n' | "$Z" set-metadata photo-renamer --idea - >/dev/null 2>&1
out=$(z get-metadata photo-renamer)
check "emoji read back" "$(j "$out" metadata.emoji)" "📷"
check "idea read back" "$(j "$out" metadata.idea)" "rename by EXIF date"
check "idea alone, byte for byte" "$("$Z" get-metadata photo-renamer --idea 2>/dev/null | od -c | tail -2 | head -1 | grep -c '\\n')" "1"
st=$("$Z" status --all --json-output 2>/dev/null)
check "status shows metadata" "$(proj "$st" photo-renamer metadata | python3 -c 'import json,sys; print(json.load(sys.stdin).get("description"))')" "Renames photos by date"

echo "up, down, disable skip folder projects"
check "up skipped" "$(j "$(z up photo-renamer)" status)" "skipped"
check "down skipped" "$(j "$(z down my-scripts)" status)" "skipped"
check "disable skipped" "$(j "$(z disable photo-renamer)" status)" "skipped"
"$Z" setup photo-renamer >/dev/null 2>&1; rc=$?
check "setup refused" "$rc" "1"
check "setup wrote no compose" "$([ -e "$P/photo-renamer/docker-compose.yaml" ] && echo yes || echo no)" "no"

echo "agent bus"
check "bus finds a created folder" "$(cd "$P/photo-renamer" && ZELTRO_PROJECTS_DIR="$P" python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); import bus; print(bus.my_project())' "$REPO/src/scripts")" "photo-renamer"
check "bus finds an added folder" "$(cd "$T/elsewhere/my-scripts" && ZELTRO_PROJECTS_DIR="$P" python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); import bus; print(bus.my_project())' "$REPO/src/scripts")" "my-scripts"

echo "a missing added folder"
mv "$T/other/my-scripts" "$T/other/gone"
st=$("$Z" status --all --json-output 2>/dev/null)
check "still listed" "$(proj "$st" my-scripts-2 kind)" "folder"
check "marked missing" "$(proj "$st" my-scripts-2 missing)" "true"
"$Z" status --all >/dev/null 2>&1; rc=$?
check "text status doesn't crash" "$rc" "0"

echo "remove"
out=$(z remove my-scripts)
check "added: success" "$(j "$out" status)" "success"
check "added: files not deleted" "$(j "$out" files_deleted)" "false"
check "added: symlink gone" "$([ -L "$P/my-scripts" ] && echo yes || echo no)" "no"
check "added: user's files untouched" "$(cat "$T/elsewhere/my-scripts/run.py")" "print('hi')"
out=$(z remove my-scripts-2)
check "missing added folder can be forgotten" "$(j "$out" status)" "success"
out=$(z remove a-docker-app)
check "docker remove says kind docker" "$(j "$out" kind)" "docker"
if command -v trash-put >/dev/null 2>&1 || command -v trash >/dev/null 2>&1; then
    out=$(z remove photo-renamer)
    check "created: trashed" "$(j "$out" files_deleted)" "true"
    check "created: folder gone" "$([ -e "$P/photo-renamer" ] && echo yes || echo no)" "no"
else
    out=$(z remove photo-renamer)
    check "created: kept without trash-cli" "$(j "$out" error)" "trash_unavailable"
fi
st=$("$Z" status --all --json-output 2>/dev/null)
check "registry empty afterwards" "$(ls "$P/.zeltro/folders" 2>/dev/null | wc -l | tr -d ' ')" "0"

echo "classifier folder candidate"
parse() { ( cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1; source scripts/classify.sh >/dev/null 2>&1; CATALOG_DIR="$REPO/src/catalog"; printf '%s' "$1" > "$T/reply"; _parse_classification "$T/reply" ); }
r=$(parse '{"project_name":"photo-renamer","recommended":"folder","customization_requested":true,"framework":{"slug":"python","reason":"x"},"apps":[],"folder":{"reason":"a script, nothing to serve"},"database":{"slug":"sqlite","reason":"x"}}')
check "folder recommended" "$(printf '%s\n' "$r" | awk -F'\t' '$1=="REC"{print $2}')" "folder"
check "folder ranked first" "$(printf '%s\n' "$r" | awk -F'\t' '$1=="CAND"{print $2; exit}')" "folder"
check "framework still offered" "$(printf '%s\n' "$r" | awk -F'\t' '$1=="CAND" && $2=="framework"{print "yes"}')" "yes"
r=$(parse '{"project_name":"bakery","recommended":"framework","framework":{"slug":"laravel","reason":"x"},"apps":[],"folder":{"reason":"could be a folder"},"database":{"slug":"mysql","reason":"x"}}')
check "folder last when not recommended" "$(printf '%s\n' "$r" | awk -F'\t' '$1=="CAND"{k=$2} END{print k}')" "folder"
r=$(parse '{"project_name":"bakery","recommended":"framework","framework":{"slug":"laravel","reason":"x"},"apps":[],"folder":null,"database":{"slug":"mysql","reason":"x"}}')
check "no folder when null" "$(printf '%s\n' "$r" | awk -F'\t' '$1=="CAND" && $2=="folder"' | wc -l | tr -d ' ')" "0"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
