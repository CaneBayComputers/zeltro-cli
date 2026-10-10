#!/bin/bash
# zeltro add <path>: make a folder you already have into a Zeltro folder project,
# without moving or copying it. The project is a symlink in the projects
# directory pointing at the folder, plus a record (see folder_projects.py).
# Nothing is written inside the folder, and `zeltro remove` only forgets it.
#
#   zeltro add <path> [--name <name>] [--json-output]

set -e

ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

TARGET=""
NAME=""
NAME_GIVEN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json-output) JSON_OUTPUT=1; shift ;;
        --name) NAME="${2:-}"; NAME_GIVEN=1; shift 2 ;;
        --name=*) NAME="${1#--name=}"; NAME_GIVEN=1; shift ;;
        --no-colors|--debug) shift ;;
        --help|-h)
            echo-white "Usage: zeltro add <path> [--name <name>] [--json-output]"
            echo-white ""
            echo-white "Use a folder you already have as a folder project: an AI session in that"
            echo-white "folder, with no container. The folder stays where it is and nothing is written"
            echo-white "inside it. 'zeltro remove' only forgets it; your files are never deleted."
            echo-white "The name defaults to the folder's name (made unique if it's taken)."
            exit 0 ;;
        -*) shift ;;
        *) [ -z "$TARGET" ] && TARGET="$1"; shift ;;
    esac
done

fail() { # <code> <message> [existing project]
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c '
import json, sys
o = {"action": "add_folder", "status": "error", "error": sys.argv[1], "message": sys.argv[2]}
if len(sys.argv) > 3 and sys.argv[3]:
    o["project_name"] = sys.argv[3]
print(json.dumps(o))' "$1" "$2" "${3:-}"
    else
        echo-red "$2"
    fi
    exit 1
}

[ -n "$TARGET" ] || fail "missing_path" "Which folder? zeltro add <path>"
TARGET="${TARGET/#\~/$HOME}"
case "$TARGET" in /*) ;; *) TARGET="$ORIG_DIR/$TARGET" ;; esac
[ -e "$TARGET" ] || fail "not_found" "There is no folder at $TARGET."
[ -d "$TARGET" ] || fail "not_a_folder" "$TARGET is a file, not a folder."
REAL="$(cd "$TARGET" && pwd -P)"

mkdir -p "$PROJECTS_DIR_PATH"
PROJECTS_REAL="$(cd "$PROJECTS_DIR_PATH" && pwd -P)"
HOME_REAL="$(cd "$HOME" && pwd -P)"

# Folders an agent shouldn't be let loose in as a whole.
case "$REAL" in
    /|"$HOME_REAL"|/home|/Users|/usr|/usr/*|/etc|/etc/*|/bin|/sbin|/var|/opt|/System|/System/*|/Library|/private/etc)
        fail "path_not_allowed" "$REAL can't be a project. Choose a folder inside it." ;;
esac
# The projects directory itself, or a folder that contains it.
case "$PROJECTS_REAL/" in
    "$REAL"/*) fail "path_not_allowed" "$REAL contains Zeltro's projects folder, so it can't be a project." ;;
esac
# Inside the projects directory: it's already a project, or inside one.
case "$REAL/" in
    "$PROJECTS_REAL"/*)
        _rel="${REAL#$PROJECTS_REAL/}"
        fail "inside_projects_dir" "$REAL is already inside Zeltro's projects folder (project '${_rel%%/*}')." "${_rel%%/*}" ;;
esac

if _existing="$(zeltro_folder_py find-path "$REAL" 2>/dev/null)"; then
    fail "already_added" "$REAL is already the project '$_existing'." "$_existing"
fi

if [ -z "$NAME" ]; then
    NAME="$(basename "$REAL")"
fi
NAME="$(zeltro_clean_project_name "$NAME")"
[ -n "$NAME" ] || NAME="folder"
if zeltro_project_name_taken "$NAME"; then
    [ "$NAME_GIVEN" = "1" ] && fail "name_taken" "There is already a project called '$NAME'." "$NAME"
    _base="$NAME"; _n=2
    while zeltro_project_name_taken "$_base-$_n"; do _n=$((_n + 1)); done
    NAME="$_base-$_n"
fi

ln -s "$REAL" "$PROJECTS_DIR_PATH/$NAME"
if ! zeltro_folder_py create "$NAME" added "$REAL"; then
    rm -f "$PROJECTS_DIR_PATH/$NAME"
    fail "registry_failed" "Couldn't record the project in $PROJECTS_DIR_PATH/.zeltro."
fi

if [[ "$JSON_OUTPUT" == "1" ]]; then
    python3 -c 'import json,sys; print(json.dumps({"action":"add_folder","project_name":sys.argv[1],"kind":"folder","origin":"added","path":sys.argv[2],"status":"success"}))' "$NAME" "$REAL"
else
    echo-green "Added '$NAME': $REAL"
    echo-white "Your files stay where they are. Start an AI session there with: zeltro resume $NAME"
fi
cd "$ORIG_DIR"
