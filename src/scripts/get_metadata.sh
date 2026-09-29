#!/bin/bash

# Read a project's x-metadata block: emoji, display name, description, the
# Create with AI idea, installer, last_on, status. The counterpart to
# set-metadata, so nothing outside the CLI has to parse docker-compose.yaml.
#
#   zeltro get-metadata <project>                 human-readable
#   zeltro get-metadata <project> --json-output   {"action","status","project","metadata":{...}}
#   zeltro get-metadata <project> --idea          just the idea, byte for byte (no newline added)

set -e

ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

PROJECT_NAME=""; ONLY_IDEA=0
JSON_OUTPUT="${JSON_OUTPUT:-}"

usage() {
    echo-white "Usage: zeltro get-metadata <project> [--idea] [--json-output]"
    echo-white ""
    echo-white "Show a project's metadata (emoji, display name, description, the Create with AI"
    echo-white "idea it came from, installer, last_on, status)."
    echo-white ""
    echo-white "Options:"
    echo-white "  --idea           Print only the idea, exactly as stored (no newline added)"
    echo-white "  --json-output    {\"action\": \"get_metadata\", \"status\": \"success\", \"project\": ..., \"metadata\": {...}}"
    echo-white "  --help           Show this message"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --idea)        ONLY_IDEA=1; shift ;;
        --json-output) JSON_OUTPUT=1; export JSON_OUTPUT; shift ;;
        --no-colors)   NO_COLOR=1; export NO_COLOR; shift ;;
        --help|-h)     usage; exit 0 ;;
        -*)            error "Unknown option: $1" ;;
        *)             if [ -z "$PROJECT_NAME" ]; then PROJECT_NAME="$1"; else error "Too many arguments"; fi; shift ;;
    esac
done

if [ -z "$PROJECT_NAME" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project name is required"
    usage; exit 1
fi
if [ ! -d "$PROJECTS_DIR_PATH/$PROJECT_NAME" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project '$PROJECT_NAME' not found"
    error "Project '$PROJECT_NAME' not found in $PROJECTS_DIR_PATH."
fi
COMPOSE_FILE="$(zeltro_project_compose "$PROJECT_NAME")"
if [ -z "$COMPOSE_FILE" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project '$PROJECT_NAME' has no docker-compose file"
    error "Project '$PROJECT_NAME' has no docker-compose file."
fi

META="$(read_x_metadata_json "$COMPOSE_FILE" full)"
[ -n "$META" ] || META="{}"

if [ "$ONLY_IDEA" = "1" ]; then
    # Byte for byte: the idea may end in newlines, so don't route it through $().
    printf '%s' "$META" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("idea",""); sys.stdout.buffer.write(v.encode("utf-8","surrogateescape"))'
elif [[ "$JSON_OUTPUT" == "1" ]]; then
    printf '{"action": "get_metadata", "status": "success", "project": "%s", "metadata": %s}\n' "$PROJECT_NAME" "$META"
else
    echo-white "Metadata for '$PROJECT_NAME':"
    printf '%s' "$META" | python3 -c '
import json, sys
m = json.load(sys.stdin)
if not m:
    print("  (none)")
for k, v in m.items():
    if k == "idea":
        continue
    print("  %-13s %s" % (k + ":", v))
if m.get("idea"):
    print("  idea:")
    for line in m["idea"].splitlines() or [""]:
        print("    " + line)
'
fi

cd "$ORIG_DIR"
