#!/bin/bash

# Write display metadata into a project's x-metadata block.
#
# Exists so nothing outside the CLI has to edit docker-compose.yaml. The GUI was
# doing it with targeted regexes, carefully enough not to disturb last_on or
# status -- which works, but makes every consumer responsible for preserving
# keys it does not own, and needs filesystem access it otherwise would not need
# once it manages remote hosts.
#
# Only the three human-editable fields are settable here. last_on is written by
# start/stop and status by enable/disable; letting them be set by hand would let
# a project claim to be enabled while parked.

set -e

ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

PROJECT_NAME=""
NEW_EMOJI=""; SET_EMOJI=0
NEW_NAME="";  SET_NAME=0
NEW_DESC="";  SET_DESC=0
IDEA_SRC="";  SET_IDEA=0   # --idea TEXT / --idea-file PATH / --idea - (stdin)
IDEA_MAX_BYTES=204800      # 200 KB
JSON_OUTPUT="${JSON_OUTPUT:-}"

usage() {
    echo-white "Usage: zeltro set-metadata <project> [options]"
    echo-white ""
    echo-white "Set the display metadata shown for a project."
    echo-white ""
    echo-white "Options:"
    echo-white "  --emoji EMOJI          Emoji shown next to the project"
    echo-white "  --name NAME            Display name (the project slug is unchanged)"
    echo-white "  --description TEXT     One-line description"
    echo-white "  --idea TEXT            The Create with AI idea the project came from (any text,"
    echo-white "                         multi-line, up to 200 KB). --idea \"\" removes it."
    echo-white "  --idea-file PATH       Read the idea from a file, byte for byte"
    echo-white "  --idea -               Read the idea from stdin (use this or --idea-file past"
    echo-white "                         ~128 KB, the limit for one command-line argument)"
    echo-white "  --json-output          Machine-readable result"
    echo-white "  --help                 Show this message"
    echo-white ""
    echo-white "last_on and status are not settable: they are written by"
    echo-white "start/stop and by 'zeltro disable'/'zeltro enable'."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --emoji)       NEW_EMOJI="${2-}"; SET_EMOJI=1; shift 2 ;;
        --name)        NEW_NAME="${2-}";  SET_NAME=1;  shift 2 ;;
        --description) NEW_DESC="${2-}";  SET_DESC=1;  shift 2 ;;
        --idea)        [ $# -ge 2 ] || error "--idea needs a value (use --idea \"\" to remove it)"
                       if [ "$2" = "-" ]; then IDEA_SRC="stdin"; else IDEA_SRC="text"; IDEA_TEXT="$2"; fi
                       SET_IDEA=1; shift 2 ;;
        --idea-file)   [ $# -ge 2 ] || error "--idea-file needs a path"
                       IDEA_SRC="file"; IDEA_FILE="$2"; SET_IDEA=1; shift 2 ;;
        --json-output) JSON_OUTPUT=1; export JSON_OUTPUT; shift ;;
        --no-colors)   NO_COLOR=1; export NO_COLOR; shift ;;
        --help|-h)     usage; exit 0 ;;
        -*)            error "Unknown option: $1" ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then PROJECT_NAME="$1"; else error "Too many arguments"; fi
            shift ;;
    esac
done

if [ -z "$PROJECT_NAME" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project name is required"
    usage; exit 1
fi

if [ "$SET_EMOJI" = "0" ] && [ "$SET_NAME" = "0" ] && [ "$SET_DESC" = "0" ] && [ "$SET_IDEA" = "0" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "nothing to set: pass --emoji, --name, --description or --idea"
    error "Nothing to set. Pass at least one of --emoji, --name, --description or --idea."
fi

# The idea goes through a temp file, never a shell variable: $(cat) would drop
# trailing newlines, and argv/env cap one string at 128 KB.
IDEA_TMP=""
if [ "$SET_IDEA" = "1" ]; then
    IDEA_TMP="$(mktemp)"; chmod 600 "$IDEA_TMP"
    trap 'rm -f "$IDEA_TMP"' EXIT
    case "$IDEA_SRC" in
        text)  printf '%s' "$IDEA_TEXT" > "$IDEA_TMP" ;;
        stdin) cat > "$IDEA_TMP" ;;
        file)  [ -f "$IDEA_FILE" ] && [ -r "$IDEA_FILE" ] || {
                   [[ "$JSON_OUTPUT" == "1" ]] && json_error "cannot read idea file: $IDEA_FILE"
                   error "Cannot read idea file: $IDEA_FILE"; }
               cat "$IDEA_FILE" > "$IDEA_TMP" ;;
    esac
    IDEA_BYTES=$(wc -c < "$IDEA_TMP" | tr -d ' ')
    if [ "$IDEA_BYTES" -gt "$IDEA_MAX_BYTES" ]; then
        [[ "$JSON_OUTPUT" == "1" ]] && json_error "idea is $IDEA_BYTES bytes; the limit is $IDEA_MAX_BYTES"
        error "The idea is $IDEA_BYTES bytes; the limit is $IDEA_MAX_BYTES (200 KB)."
    fi
fi

PROJECT_DIR="$PROJECTS_DIR_PATH/$PROJECT_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project '$PROJECT_NAME' not found"
    error "Project '$PROJECT_NAME' not found in $PROJECTS_DIR_PATH."
fi

COMPOSE_FILE="$(zeltro_project_compose "$PROJECT_NAME")"
if [ -z "$COMPOSE_FILE" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project '$PROJECT_NAME' has no docker-compose file"
    error "Project '$PROJECT_NAME' has no docker-compose file. Run: zeltro setup $PROJECT_NAME"
fi

_fail() {
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "could not write project metadata"
    error "Could not update project metadata."
}

# Written one key at a time on purpose: set_x_metadata_key rewrites only the key
# it is given, so keys this command does not own (last_on, status) are never at
# risk of being dropped by a bulk rewrite.
[ "$SET_EMOJI" = "1" ] && { set_x_metadata_key "$COMPOSE_FILE" "$PROJECT_NAME" "emoji"       "$NEW_EMOJI" || _fail; }
[ "$SET_NAME"  = "1" ] && { set_x_metadata_key "$COMPOSE_FILE" "$PROJECT_NAME" "name"        "$NEW_NAME"  || _fail; }
[ "$SET_DESC"  = "1" ] && { set_x_metadata_key "$COMPOSE_FILE" "$PROJECT_NAME" "description" "$NEW_DESC"  || _fail; }
if [ "$SET_IDEA" = "1" ]; then
    if [ "$IDEA_BYTES" = "0" ]; then
        set_x_metadata_key_file "$COMPOSE_FILE" "$PROJECT_NAME" "idea" "$IDEA_TMP" delete || _fail
    else
        set_x_metadata_key_file "$COMPOSE_FILE" "$PROJECT_NAME" "idea" "$IDEA_TMP" || _fail
    fi
fi

UPDATED="$(read_x_metadata_json "$COMPOSE_FILE")"
[ -n "$UPDATED" ] || UPDATED="{}"

if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "{\"action\": \"set_metadata\", \"status\": \"success\", \"project\": \"$PROJECT_NAME\", \"metadata\": $UPDATED}"
else
    echo-green "Metadata updated for '$PROJECT_NAME'."
    [ "$SET_EMOJI" = "1" ] && echo-white "  emoji:       $NEW_EMOJI"
    [ "$SET_NAME"  = "1" ] && echo-white "  name:        $NEW_NAME"
    [ "$SET_DESC"  = "1" ] && echo-white "  description: $NEW_DESC"
    if [ "$SET_IDEA" = "1" ]; then
        if [ "$IDEA_BYTES" = "0" ]; then echo-white "  idea:        (removed)"; else echo-white "  idea:        $IDEA_BYTES bytes (read it with: zeltro get-metadata $PROJECT_NAME --idea)"; fi
    fi
fi

cd "$ORIG_DIR"
