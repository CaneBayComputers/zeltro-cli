#!/bin/bash
# zeltro peers / zeltro send / zeltro gui -- agent sessions talking to each other
# and to the Zeltro app. The logic is in bus.py and gui.py (it is all JSON); this
# only supplies the projects directory, which is how the sender is identified.
# No pre_check: messaging needs neither Docker nor sudo.

DEV_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
source "$DEV_DIR/scripts/functions.sh"

if [ "$1" = "gui" ]; then
    ZELTRO_PROJECTS_DIR="$(get_projects_dir)" exec python3 "$DEV_DIR/scripts/gui.py" "${@:2}"
fi
ZELTRO_PROJECTS_DIR="$(get_projects_dir)" exec python3 "$DEV_DIR/scripts/bus.py" "$@"
