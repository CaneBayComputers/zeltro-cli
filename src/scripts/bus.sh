#!/bin/bash
# zeltro peers / zeltro send -- agent-to-agent messages routed by the Zeltro app.
# The logic is in bus.py (it is all JSON); this only supplies the projects
# directory, which is how the sender is identified. No pre_check: messaging
# needs neither Docker nor sudo.

DEV_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
source "$DEV_DIR/scripts/functions.sh"

ZELTRO_PROJECTS_DIR="$(get_projects_dir)" exec python3 "$DEV_DIR/scripts/bus.py" "$@"
