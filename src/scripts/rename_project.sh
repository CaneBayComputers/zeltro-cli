#!/bin/bash
# zeltro rename <project> <new-name>: give a project a new name. Its folder in
# the projects directory moves to the new name and everything Zeltro keys on the
# name follows it:
#
#   Docker project   the web container (container_name), the compose project and
#                    so its named volumes (<name>_<volume>: copied, verified, the
#                    old ones removed) and locally built images (<name>-<service>:
#                    retagged). Stopped first and started again if it was running.
#                    The address, port, database and .env are unchanged.
#   Folder project   created: the folder moves and its record and AGENTS.md
#                    follow. Added: only the name (the link and the record); the
#                    user's folder stays where it is, untouched.
#   Every kind       Claude Code's conversation history for the folder moves too,
#                    so `zeltro resume` carries on. With --github, the GitHub repo
#                    behind origin is renamed and origin updated (GitHub redirects
#                    the old URL).
#
# Refused while any process has its working directory inside the project (an
# open AI session or terminal there would be left in a folder that no longer
# exists); --force skips that check.
#
#   zeltro rename <project> <new-name> [--github] [--dry-run] [--force] [--json-output]

set -e

ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

OLD=""; NEW_RAW=""; GITHUB=0; DRY_RUN=0; FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json-output) JSON_OUTPUT=1; shift ;;
        --github) GITHUB=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        --no-colors|--debug) shift ;;
        --help|-h)
            echo-white "Usage: zeltro rename <project> <new-name> [--github] [--dry-run] [--force] [--json-output]"
            echo-white ""
            echo-white "Rename a project: its folder, its container and data volumes, and its AI"
            echo-white "conversation history. Its address, port, database and settings stay the same."
            echo-white "A running project is stopped and started again under the new name. For a folder"
            echo-white "you added with 'zeltro add', only the project's name changes; the folder stays put."
            echo-white ""
            echo-white "  --github    Also rename the GitHub repo behind 'origin' and point origin at it"
            echo-white "  --dry-run   Show what would change (with --json-output: whether --github can work)"
            echo-white "  --force     Rename even though a program is running inside the project folder"
            exit 0 ;;
        -*) shift ;;
        *) if [ -z "$OLD" ]; then OLD="$1"; elif [ -z "$NEW_RAW" ]; then NEW_RAW="$1"; fi; shift ;;
    esac
done

fail() { # <code> <message> [extra json object]
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c '
import json, sys
o = {"action": "rename", "status": "error", "error": sys.argv[1], "message": sys.argv[2]}
if len(sys.argv) > 3 and sys.argv[3]:
    o.update(json.loads(sys.argv[3]))
print(json.dumps(o))' "$1" "$2" "${3:-}"
    else
        echo-red "$2"
    fi
    exit 1
}
say() { [[ "$JSON_OUTPUT" == "1" ]] || echo-white "$@"; }
step() { [[ "$JSON_OUTPUT" == "1" ]] || echo-cyan "$@"; }

[ -n "$OLD" ] || fail "missing_name" "Which project? zeltro rename <project> <new-name>"
P="$PROJECTS_DIR_PATH"
OLD_PATH="$P/$OLD"
if ! { [ -e "$OLD_PATH" ] || [ -L "$OLD_PATH" ] || [ -f "$P/.zeltro/folders/$OLD.json" ]; }; then
    fail "not_found" "There is no project called '$OLD'."
fi
case "$OLD" in */*|.*) fail "not_found" "There is no project called '$OLD'." ;; esac

NEW=""
if [ -n "$NEW_RAW" ]; then
    NEW="$(zeltro_clean_project_name "$NEW_RAW")"
    [ -n "$NEW" ] || fail "bad_name" "Project names use letters, numbers, dashes and underscores."
    [ "$NEW" != "$OLD" ] || fail "same_name" "'$OLD' already has that name."
    zeltro_project_name_taken "$NEW" && fail "name_taken" "There is already a project called '$NEW'."
elif [ "$DRY_RUN" != "1" ]; then
    fail "missing_name" "What should '$OLD' be called? zeltro rename $OLD <new-name>"
fi

# --- What kind of project, and what it owns -----------------------------------
KIND="docker"; ORIGIN=""
if zeltro_project_is_folder "$OLD"; then
    KIND="folder"
    ORIGIN="$(zeltro_folder_py info "$OLD" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("origin","created"))' 2>/dev/null || echo created)"
fi
# Where the project's files really are (an added folder: the folder it links to).
OLD_REAL="$(cd "$OLD_PATH" 2>/dev/null && pwd -P || true)"

COMPOSE=""
if [ "$KIND" = "docker" ]; then
    for f in docker-compose.yaml docker-compose.yml; do
        [ -f "$OLD_PATH/$f" ] && { COMPOSE="$f"; break; }
    done
fi
HAS_DOCKER=0
[ -n "$COMPOSE" ] && command -v docker >/dev/null 2>&1 && HAS_DOCKER=1

WAS_RUNNING=0
VOL_KEYS=""      # compose volume keys whose volume is <OLD>_<key>
BUILT_SVCS=""    # services whose image compose built as <OLD>-<service>
if [ "$HAS_DOCKER" = "1" ]; then
    docker container inspect -f '{{.State.Running}}' "$OLD" 2>/dev/null | grep -q true && WAS_RUNNING=1
    # Volumes are found by the labels compose puts on them, not by a name
    # prefix: "foo_" would also match every volume of a project called foo_bar.
    for v in $(docker volume ls -q --filter "label=com.docker.compose.project=$OLD" 2>/dev/null); do
        k="$(docker volume inspect -f '{{index .Labels "com.docker.compose.volume"}}' "$v" 2>/dev/null || true)"
        # A volume the compose names itself (volumes: x: name: ...) keeps its name.
        [ -n "$k" ] && [ "$v" = "${OLD}_${k}" ] && VOL_KEYS="$VOL_KEYS $k"
    done
    BUILT_SVCS="$( (cd "$OLD_PATH" && docker compose config --format json 2>/dev/null) | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for name, svc in (d.get("services") or {}).items():
    if svc.get("build") and not svc.get("image", "").strip():
        print(name)' 2>/dev/null || true)"
    # compose config fills in image: for built services on newer versions; fall
    # back to whatever local image carries the compose name.
    for img in $(docker image ls --format '{{.Repository}}' 2>/dev/null | grep "^${OLD}-" || true); do
        s="${img#${OLD}-}"
        case " $BUILT_SVCS " in *" $s "*) ;; *) docker compose -f "$OLD_PATH/$COMPOSE" config --services 2>/dev/null | grep -qx "$s" && BUILT_SVCS="$BUILT_SVCS $s" ;; esac
    done
fi

# Clashes with Docker objects already using the new name.
if [ -n "$NEW" ] && [ "$HAS_DOCKER" = "1" ]; then
    docker container inspect "$NEW" >/dev/null 2>&1 \
        && fail "container_exists" "A container called '$NEW' already exists. Remove it, or choose another name."
    [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=$NEW" 2>/dev/null)" ] \
        || fail "container_exists" "Containers from an earlier '$NEW' project still exist. Remove them (docker compose -p $NEW down), or choose another name."
    for k in $VOL_KEYS; do
        docker volume inspect "${NEW}_${k}" >/dev/null 2>&1 \
            && fail "volume_exists" "A Docker volume called '${NEW}_${k}' already exists (left by an earlier '$NEW' project?). Remove it, or choose another name."
    done
fi

# --- GitHub ----------------------------------------------------------------------
GH_REPO=""; GH_CAN=0; GH_WHY=""
ORIGIN_URL=""
if [ -n "$OLD_REAL" ] && command -v git >/dev/null 2>&1; then
    ORIGIN_URL="$(git -C "$OLD_REAL" remote get-url origin 2>/dev/null || true)"
fi
GH_REPO="$(printf '%s' "$ORIGIN_URL" | python3 -c '
import re, sys
m = re.search(r"github\.com[:/]+([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", sys.stdin.read().strip())
print(m.group(1) + "/" + m.group(2) if m else "")' 2>/dev/null || true)"
if [ -z "$GH_REPO" ]; then
    GH_WHY="no_github_remote"
elif ! command -v gh >/dev/null 2>&1; then
    GH_WHY="gh_not_installed"
else
    _perm="$(gh repo view "$GH_REPO" --json viewerPermission -q .viewerPermission 2>/dev/null || true)"
    case "$_perm" in
        ADMIN) GH_CAN=1 ;;
        "") GH_WHY="gh_unavailable" ;;   # not signed in, offline, or no such repo
        *) GH_WHY="not_repo_admin" ;;
    esac
fi
if [ "$GITHUB" = "1" ] && [ "$GH_CAN" != "1" ]; then
    case "$GH_WHY" in
        no_github_remote) _m="This project's origin isn't a GitHub repo, so there's no GitHub repo to rename." ;;
        gh_not_installed) _m="Renaming the GitHub repo needs the GitHub CLI (gh), which isn't installed." ;;
        not_repo_admin)   _m="You don't have admin rights on $GH_REPO, so it can't be renamed from here." ;;
        *)                _m="Couldn't reach $GH_REPO on GitHub. Check 'gh auth status', or rename without --github." ;;
    esac
    fail "github_unavailable" "$_m" "{\"github_reason\": \"$GH_WHY\"}"
fi

# --- Anything still working inside the folder? -----------------------------------
# A shell, editor or AI session there would carry on under the old path: an AI
# session keeps writing its history under the old name, a terminal's prompt
# shows a folder that no longer exists. Whatever ran this command (the user's
# own shell, the app) is left out.
procs_in_dir() { # <real dir>: "pid name" per process whose cwd is inside it
    local d="$1" p c
    if [ -d /proc/self ]; then
        for p in /proc/[0-9]*; do
            c="$(readlink "$p/cwd" 2>/dev/null)" || continue
            case "$c/" in "$d"/*) echo "${p#/proc/} $(cat "$p/comm" 2>/dev/null)" ;; esac
        done
    elif command -v lsof >/dev/null 2>&1; then
        lsof -a -d cwd -Fpcn 2>/dev/null | python3 -c '
import sys
d = sys.argv[1].rstrip("/") + "/"
pid = name = None
for line in sys.stdin:
    t, v = line[:1], line[1:].rstrip("\n")
    if t == "p": pid = v
    elif t == "c": name = v
    elif t == "n" and (v.rstrip("/") + "/").startswith(d):
        print(pid, name)' "$d"
    fi
}
# Only for a folder that moves: renaming an added folder never moves anything.
MOVES_FOLDER=1
[ "$KIND" = "folder" ] && [ "$ORIGIN" = "added" ] && MOVES_FOLDER=0
BUSY=""
if [ "$MOVES_FOLDER" = "1" ] && [ -n "$OLD_REAL" ] && [ "$FORCE" != "1" ]; then
    _mine=" $$ "; _p="$PPID"
    while [ -n "$_p" ] && [ "$_p" -gt 1 ] 2>/dev/null; do
        _mine="$_mine$_p "; _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"
    done
    # ...and the rest of its pipeline (zeltro rename ... | tail), by process group.
    _pg="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
    BUSY="$(procs_in_dir "$OLD_REAL" | while read -r _pid _name; do
        case "$_mine" in *" $_pid "*) continue ;; esac
        [ -n "$_pg" ] && [ "$(ps -o pgid= -p "$_pid" 2>/dev/null | tr -d ' ')" = "$_pg" ] && continue
        echo "$_pid $_name"
    done)"
fi

# --- Dry run ----------------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 - "$OLD" "$NEW" "$KIND" "$ORIGIN" "$WAS_RUNNING" "$VOL_KEYS" "$BUILT_SVCS" "$GH_REPO" "$GH_CAN" "$GH_WHY" "$BUSY" <<'PYEOF'
import json, sys
old, new, kind, origin, running, vols, built, repo, can, why, busy = sys.argv[1:12]
o = {"action": "rename", "status": "preview", "old_name": old, "project_name": new or None,
     "kind": kind, "running": running == "1",
     "volumes": [{"from": old + "_" + k, "to": (new + "_" + k) if new else None} for k in vols.split()],
     "images": [{"from": old + "-" + s, "to": (new + "-" + s) if new else None} for s in built.split()],
     "github": {"repo": repo or None, "can_rename": can == "1", "reason": why or None},
     "in_use": [{"pid": int(l.split(" ", 1)[0]), "name": l.split(" ", 1)[1] if " " in l else ""}
                for l in busy.splitlines() if l.strip()]}
if kind == "folder":
    o["origin"] = origin
print(json.dumps(o))
PYEOF
    else
        echo-white "Rename '$OLD'${NEW:+ to '$NEW'} ($KIND project${ORIGIN:+, $ORIGIN})"
        [ "$WAS_RUNNING" = "1" ] && echo-white "  It's running: it will be stopped and started again."
        for k in $VOL_KEYS; do echo-white "  Volume ${OLD}_${k} -> ${NEW:-<new>}_${k} (copied and verified)"; done
        for s in $BUILT_SVCS; do echo-white "  Image ${OLD}-${s} -> ${NEW:-<new>}-${s}"; done
        if [ -n "$GH_REPO" ]; then
            [ "$GH_CAN" = "1" ] && echo-white "  GitHub repo $GH_REPO can be renamed too (--github)" \
                                || echo-white "  GitHub repo $GH_REPO can't be renamed from here ($GH_WHY)"
        fi
        [ -n "$BUSY" ] && echo-yellow "  In use by: $(echo "$BUSY" | awk '{print $2" ("$1")"}' | tr '\n' ' ')"
        echo-white "Nothing was changed."
    fi
    exit 0
fi

if [ -n "$BUSY" ]; then
    _list="$(echo "$BUSY" | awk '{print $2" ("$1")"}' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    fail "in_use" "Close what's running inside '$OLD' first: $_list. (A terminal there? cd out of it.)" \
        "$(echo "$BUSY" | python3 -c 'import json,sys; print(json.dumps({"in_use":[{"pid":int(l.split(" ",1)[0]),"name":(l.split(" ",1)+[""])[1]} for l in sys.stdin.read().splitlines() if l.strip()]}))')"
fi

# --- Rename -----------------------------------------------------------------------
NEW_PATH="$P/$NEW"
CREATED_VOLS=""
put_back() {
    for nv in $CREATED_VOLS; do docker volume rm "$nv" >/dev/null 2>&1 || true; done
    if [ "$WAS_RUNNING" = "1" ]; then "$DEV_DIR/zeltro" up "$OLD" >/dev/null 2>&1 || true; fi
}

if [ "$HAS_DOCKER" = "1" ]; then
    if [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$OLD" 2>/dev/null)" ] \
        || docker container inspect "$OLD" >/dev/null 2>&1; then
        step "Stopping $OLD ..."
        (cd "$OLD_PATH" && docker compose down --remove-orphans >/dev/null 2>&1) || true
        docker container inspect "$OLD" >/dev/null 2>&1 && docker rm -f "$OLD" >/dev/null 2>&1 || true
    fi
    for k in $VOL_KEYS; do
        v="${OLD}_${k}"; nv="${NEW}_${k}"
        step "Copying volume $v -> $nv ..."
        docker volume create --label "com.docker.compose.project=$NEW" --label "com.docker.compose.volume=$k" "$nv" >/dev/null \
            || { put_back; fail "volume_copy_failed" "Couldn't create the volume $nv. Nothing was renamed."; }
        CREATED_VOLS="$CREATED_VOLS $nv"
        if ! docker run --rm -v "$v":/from:ro -v "$nv":/to alpine:3 sh -c 'cp -a /from/. /to/' >/dev/null 2>&1; then
            put_back; fail "volume_copy_failed" "Copying $v failed. Nothing was renamed; '$OLD' is as it was."
        fi
        a="$(zeltro_volume_fingerprint "$v")"; b="$(zeltro_volume_fingerprint "$nv")"
        if [ -z "$a" ] || [ "$a" != "$b" ]; then
            put_back; fail "volume_copy_failed" "The copy of $v doesn't match the original. Nothing was renamed; '$OLD' is as it was."
        fi
    done
fi

step "Renaming $OLD -> $NEW ..."
if ! mv "$OLD_PATH" "$NEW_PATH" 2>/dev/null; then
    put_back; fail "move_failed" "Couldn't rename the folder $OLD_PATH. Nothing was renamed."
fi
NEW_REAL="$(cd "$NEW_PATH" 2>/dev/null && pwd -P || true)"

if [ "$KIND" = "folder" ]; then
    if [ "$ORIGIN" = "added" ]; then
        zeltro_folder_py rename "$OLD" "$NEW" >/dev/null
    else
        zeltro_folder_py rename "$OLD" "$NEW" "$NEW_REAL" >/dev/null
        grep -q "BEGIN ZELTRO CONTEXT" "$NEW_PATH/AGENTS.md" 2>/dev/null \
            && zeltro_write_folder_agents_md "$NEW_PATH" "$NEW"
    fi
fi

# The web container is the one named after the project (and x-metadata hangs off
# it). Other container_names are the app's own and stay.
if [ -n "$COMPOSE" ]; then
    python3 - "$NEW_PATH/$COMPOSE" "$OLD" "$NEW" <<'PYEOF'
import re, sys
path, old, new = sys.argv[1:4]
s = open(path, encoding="utf-8").read()
pat = re.compile(r'^(\s*container_name:\s*)(["\']?)' + re.escape(old) + r'\2(\s*(?:#.*)?)$', re.M)
s2 = pat.sub(lambda m: m.group(1) + m.group(2) + new + m.group(2) + m.group(3), s)
if s2 != s:
    open(path, "w", encoding="utf-8").write(s2)
PYEOF
fi

MOVED_VOLS=""; KEPT_VOLS=""
for k in $VOL_KEYS; do
    if docker volume rm "${OLD}_${k}" >/dev/null 2>&1; then MOVED_VOLS="$MOVED_VOLS $k"; else KEPT_VOLS="$KEPT_VOLS ${OLD}_${k}"; fi
done
for s in $BUILT_SVCS; do
    if docker image inspect "${OLD}-${s}" >/dev/null 2>&1; then
        docker tag "${OLD}-${s}" "${NEW}-${s}" >/dev/null 2>&1 && docker image rm "${OLD}-${s}" >/dev/null 2>&1 || true
    fi
done

# Claude Code keeps a folder's conversations in ~/.claude/projects/<path with
# every non-alphanumeric character as "-">; move them so `--continue` finds them.
AI_HISTORY=0
if [ "$MOVES_FOLDER" = "1" ] && [ -n "$OLD_REAL" ] && [ -n "$NEW_REAL" ] && [ "$OLD_REAL" != "$NEW_REAL" ]; then
    AI_HISTORY="$(python3 - "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" "$OLD_REAL" "$NEW_REAL" <<'PYEOF' 2>/dev/null || echo 0
import os, re, shutil, sys
root, old, new = sys.argv[1:4]
enc = lambda p: re.sub(r"[^a-zA-Z0-9]", "-", p)
src, dst = os.path.join(root, enc(old)), os.path.join(root, enc(new))
if not os.path.isdir(src):
    print(0); sys.exit(0)
if not os.path.exists(dst):
    os.rename(src, dst)
else:
    for f in os.listdir(src):
        if not os.path.exists(os.path.join(dst, f)):
            shutil.move(os.path.join(src, f), os.path.join(dst, f))
print(1)
PYEOF
)"
    # Its per-folder settings in ~/.claude.json (trust, allowed tools) follow too.
    if [ -f "$HOME/.claude.json" ]; then
        python3 - "$HOME/.claude.json" "$OLD_REAL" "$NEW_REAL" <<'PYEOF' >/dev/null 2>&1 || true
import json, os, sys, tempfile
path, old, new = sys.argv[1:4]
for _ in range(5):
    before = os.stat(path).st_mtime_ns
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    projects = data.get("projects") or {}
    if old not in projects or new in projects:
        sys.exit(0)
    projects[new] = projects.pop(old)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".claude.json.zeltro-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    if os.stat(path).st_mtime_ns == before:
        os.replace(tmp, path)
        sys.exit(0)
    os.remove(tmp)                       # Claude wrote it meanwhile: try again
PYEOF
    fi
    zeltro_trust_project_for_agents "$NEW_PATH" >/dev/null 2>&1 || true
fi

# GitHub last: the local rename is done whatever happens here.
GH_RENAMED=0; GH_NEW=""; GH_ERR=""
if [ "$GITHUB" = "1" ]; then
    _owner="${GH_REPO%%/*}"; _repo="${GH_REPO#*/}"
    GH_NEW="$_owner/$NEW"
    step "Renaming GitHub repo $GH_REPO -> $GH_NEW ..."
    if [ "$_repo" = "$NEW" ] || GH_ERR="$(gh repo rename "$NEW" --repo "$GH_REPO" --yes 2>&1)"; then
        GH_RENAMED=1; GH_ERR=""
        _url="$(printf '%s' "$ORIGIN_URL" | python3 -c '
import re, sys
print(re.sub(r"/[^/\s]+?(\.git)?/?$", lambda m: "/" + sys.argv[1] + (m.group(1) or ""), sys.stdin.read().strip(), count=1))' "$NEW")"
        git -C "$NEW_REAL" remote set-url origin "$_url" 2>/dev/null || true
    else
        GH_ERR="$(printf '%s' "$GH_ERR" | tail -n 1)"
    fi
fi

RESTARTED=0; START_ERR=""
if [ "$WAS_RUNNING" = "1" ]; then
    step "Starting $NEW ..."
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        if _out="$("$DEV_DIR/zeltro" up "$NEW" --json-output 2>&1)"; then RESTARTED=1; else START_ERR="$(printf '%s' "$_out" | tail -n 1)"; fi
    else
        if "$DEV_DIR/zeltro" up "$NEW"; then RESTARTED=1; else START_ERR="failed"; fi
    fi
fi

if [[ "$JSON_OUTPUT" == "1" ]]; then
    python3 - "$OLD" "$NEW" "$KIND" "$ORIGIN" "${NEW_REAL:-$NEW_PATH}" "$WAS_RUNNING" "$RESTARTED" "$START_ERR" \
        "$MOVED_VOLS" "$KEPT_VOLS" "$AI_HISTORY" "$GITHUB" "$GH_REPO" "$GH_NEW" "$GH_RENAMED" "$GH_ERR" <<'PYEOF'
import json, sys
(old, new, kind, origin, path, was, restarted, start_err, moved, kept, hist,
 gh, gh_repo, gh_new, gh_done, gh_err) = sys.argv[1:17]
o = {"action": "rename", "status": "success", "old_name": old, "project_name": new,
     "kind": kind, "path": path, "was_running": was == "1", "restarted": restarted == "1",
     "volumes_moved": [new + "_" + k for k in moved.split()],
     "ai_history_moved": hist == "1"}
if kind == "folder":
    o["origin"] = origin
if start_err:
    o["start_error"] = start_err
if kept.split():
    o["old_volumes_kept"] = kept.split()
if gh == "1":
    o["github"] = {"repo": gh_new if gh_done == "1" else gh_repo, "renamed": gh_done == "1"}
    if gh_err:
        o["github"]["error"] = gh_err
print(json.dumps(o))
PYEOF
    exit 0
fi

echo-green "Renamed '$OLD' to '$NEW'."
[ "$KIND" = "folder" ] && [ "$ORIGIN" = "added" ] && echo-white "Your folder is still at $NEW_REAL."
[ -n "$KEPT_VOLS" ] && echo-yellow "These old volumes couldn't be removed (the data is in the new ones):$KEPT_VOLS"
[ "$GITHUB" = "1" ] && { [ "$GH_RENAMED" = "1" ] && echo-white "GitHub repo is now $GH_NEW." || echo-yellow "The GitHub repo wasn't renamed: $GH_ERR"; }
[ -n "$START_ERR" ] && echo-yellow "It didn't start again. Try: zeltro up $NEW"
cd "$ORIG_DIR" 2>/dev/null || true
