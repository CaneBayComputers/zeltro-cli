#!/bin/bash
# zeltro uninstall: remove Zeltro's containers and networks, and on request its
# images and data volumes, or (--purge) everything Zeltro put on the machine
# except the projects folder.
#
# Never prompts. Every removal is checked afterwards, the summary lists what
# actually happened, and anything left behind is listed with a non-zero exit.
# Files in the projects folder are never touched, and nothing outside Zeltro's
# own resources is: no machine-wide prune, no disconnecting other containers.
#
# The old script (until 2026-10-22) read container names out of the compose
# file as text, so it looked up `"${MARIADB_CONTAINER_NAME:-zeltro-mariadb}"`
# literally and stopped none of the services; it then reported volumes and
# images removed that Docker had refused, pulled the network out from under the
# still-running services, renamed every project's docker-compose.yaml, ran
# `docker system prune -f`, and asked a question no agent could answer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

# Tests point every system path at a scratch tree with this; nothing else sets it.
R="${ZELTRO_TEST_ROOT:-}"

DELETE_IMAGES=0
DELETE_DATA=0
PURGE=0

usage() {
    echo-white "Usage: ${ZELTRO_CMD:-zeltro uninstall} [options]"
    echo-white ""
    echo-white "Stops and removes every Zeltro service container and project container, then"
    echo-white "Zeltro's networks and the Zeltro CLI. Never asks a question."
    echo-white ""
    echo-white "Kept by default: Docker images, the zeltro-cli_* data volumes (your databases),"
    echo-white "/etc/zeltro-cli, the app's settings and everything in the projects folder."
    echo-white ""
    echo-white "Options:"
    echo-white "  --delete-images   Also remove the images those containers used"
    echo-white "  --delete-data     Also remove the zeltro-cli_* volumes (ALL shared databases)"
    echo-white "  --purge           Everything Zeltro put on this machine except the projects folder:"
    echo-white "                    both of the above, plus the Zeltro app, /etc/zeltro-cli, the Zeltro"
    echo-white "                    package repository and key, bash completion, ~/.zeltro, ~/.cache/zeltro,"
    echo-white "                    the app's settings and its update downloads. Docker, Node and git stay."
    echo-white "  --json-output     One JSON object instead of text"
    echo-white "  --help            Show this help"
    echo-white ""
    echo-white "Exit status: 0 when everything asked for was removed, 1 when something was left"
    echo-white "(each leftover is listed)."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --json-output) JSON_OUTPUT=1 ;;
        --debug) DEBUG=1 ;;
        --delete-images) DELETE_IMAGES=1 ;;
        --delete-data) DELETE_DATA=1 ;;
        --purge) PURGE=1; DELETE_IMAGES=1; DELETE_DATA=1 ;;
        --help|-h) usage; exit 0 ;;
        -*) error "Unknown option: $1. Use --help for usage information" ;;
        *) error "Unexpected argument: $1. Use --help for usage information" ;;
    esac
    shift
done

if ! docker info >/dev/null 2>&1; then
    error "Docker is not running or not accessible. Start Docker and try again; nothing was changed."
fi

REMOVED=()
LEFT=()
removed() { REMOVED+=("$1"); echo-white "  removed $1"; }
left()    { LEFT+=("$1"); echo-yellow "  NOT removed: $1"; }

# Run as root when needed, without hanging on a password prompt that no one can
# see (the app and agents run us with no terminal).
as_root() {
    "$@" 2>/dev/null && return 0
    [ "$(id -u)" = "0" ] && return 1
    [ -n "$R" ] && return 1      # under test: never the real sudo
    if [ -t 0 ]; then sudo "$@"; else sudo -n "$@"; fi
}

# Remove one path (file, directory or link) and record the outcome.
remove_path() { # <path> [root]
    local f="$1"
    [ -e "$f" ] || [ -L "$f" ] || return 0
    if [ "${2:-}" = "root" ]; then
        if [ -d "$f" ] && [ ! -L "$f" ]; then as_root rm -rf "$f"; else as_root rm -f "$f"; fi
    else
        if [ -d "$f" ] && [ ! -L "$f" ]; then rm -rf "$f"; else rm -f "$f"; fi
    fi 2>/dev/null
    if [ -e "$f" ] || [ -L "$f" ]; then left "$f"; else removed "$f"; fi
}

# Remove an installed package (the GUI, or the CLI's own package) with
# whichever package manager has it. Never prompts.
remove_package() { # <name>
    local name="$1"
    if command -v dpkg >/dev/null 2>&1 && dpkg -s "$name" >/dev/null 2>&1; then
        as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y -q "$name" >/dev/null 2>&1
        if dpkg -s "$name" >/dev/null 2>&1; then left "package $name"; else removed "package $name"; fi
    elif command -v rpm >/dev/null 2>&1 && rpm -q "$name" >/dev/null 2>&1; then
        as_root dnf remove -y -q "$name" >/dev/null 2>&1
        if rpm -q "$name" >/dev/null 2>&1; then left "package $name"; else removed "package $name"; fi
    elif command -v pacman >/dev/null 2>&1 && pacman -Q "$name" >/dev/null 2>&1; then
        as_root pacman -Rns --noconfirm "$name" >/dev/null 2>&1
        if pacman -Q "$name" >/dev/null 2>&1; then left "package $name"; else removed "package $name"; fi
    fi
    return 0
}

# The projects folder, resolved, so container working dirs can be matched to it.
PROJECTS_DIR=$(get_projects_dir 2>/dev/null || true)
PROJECTS_DIR_REAL=""
[ -n "$PROJECTS_DIR" ] && [ -d "$PROJECTS_DIR" ] && PROJECTS_DIR_REAL=$(cd "$PROJECTS_DIR" && pwd -P)

under_projects_dir() { # <path>
    [ -n "$1" ] || return 1
    case "$1/" in
        "$PROJECTS_DIR_REAL"/?*|"$PROJECTS_DIR"/?*) [ -n "$PROJECTS_DIR" ] ;;
        *) return 1 ;;
    esac
}

SERVICE_NAMES_RE="^(zeltro|${SERVICE_PREFIX:-zeltro})-(mariadb|redis|postgres|mongo|memcached|phpmyadmin|mailhog|minio|meilisearch|adminer|mongo-express|redisinsight)$"

# --- 1. Containers ---------------------------------------------------------------
# Services: the compose project "zeltro-cli" (/etc/zeltro-cli), or a service's
# exact name. Projects: any container whose compose working dir is inside the
# projects folder (an installed app can run several), or one named after a
# project directory there. Folder projects have no container, and one added
# from elsewhere is a symlink whose compose files belong to its owner.
echo-cyan "Removing Zeltro containers ..."
TARGETS=()
IMAGES=()
COMPOSE_PROJECTS=()
while IFS=$'\t' read -r name project wdir image; do
    [ -n "$name" ] || continue
    keep=1
    if [ "$project" = "zeltro-cli" ] || [[ "$name" =~ $SERVICE_NAMES_RE ]]; then
        keep=0
    elif under_projects_dir "$wdir"; then
        keep=0
    elif [ -n "$PROJECTS_DIR" ] && [ -d "$PROJECTS_DIR/$name" ] && [ ! -L "$PROJECTS_DIR/$name" ] \
         && [ ! -f "$PROJECTS_DIR/.zeltro/folders/$name.json" ]; then
        keep=0
    fi
    [ "$keep" = "1" ] && continue
    TARGETS+=("$name")
    IMAGES+=("$image")
    [ -n "$project" ] && COMPOSE_PROJECTS+=("$project")
done < <(docker ps -a --format '{{.Names}}	{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.project.working_dir"}}	{{.Image}}' 2>/dev/null)

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo-white "  no Zeltro containers found"
fi
for name in ${TARGETS[@]+"${TARGETS[@]}"}; do
    if [ "$DELETE_DATA" = "1" ]; then docker rm -f -v "$name" >/dev/null 2>&1; else docker rm -f "$name" >/dev/null 2>&1; fi
    if docker container inspect "$name" >/dev/null 2>&1; then
        left "container $name"
    else
        removed "container $name"
    fi
done
echo-return

# --- 2. Networks -------------------------------------------------------------------
# Zeltro's VPC and any network a removed project's compose created. One that
# still has containers attached is not ours alone: report it, never disconnect.
echo-cyan "Removing Zeltro networks ..."
NETWORKS=$(
    {
        docker network ls --filter label=com.docker.compose.project=zeltro-cli --format '{{.Name}}'
        docker network ls --format '{{.Name}}' | grep -E '^zeltro-cli_' || true
        for p in ${COMPOSE_PROJECTS[@]+"${COMPOSE_PROJECTS[@]}"}; do
            [ "$p" = "zeltro-cli" ] && continue
            docker network ls --filter "label=com.docker.compose.project=$p" --format '{{.Name}}'
        done
    } 2>/dev/null | sort -u
)
[ -n "$NETWORKS" ] || echo-white "  no Zeltro networks found"
for net in $NETWORKS; do
    users=$(docker network inspect "$net" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
    if [ -n "${users// /}" ]; then
        left "network $net (still used by: ${users% })"
        continue
    fi
    docker network rm "$net" >/dev/null 2>&1
    if docker network inspect "$net" >/dev/null 2>&1; then left "network $net"; else removed "network $net"; fi
done
echo-return

# --- 3. Data volumes ---------------------------------------------------------------
VOLUMES=$(
    {
        docker volume ls --filter label=com.docker.compose.project=zeltro-cli --format '{{.Name}}'
        docker volume ls --format '{{.Name}}' | grep -E '^zeltro-cli_' || true
    } 2>/dev/null | sort -u
)
KEPT_VOLUMES=""
if [ "$DELETE_DATA" = "1" ]; then
    echo-cyan "Removing Zeltro data volumes ..."
    [ -n "$VOLUMES" ] || echo-white "  no Zeltro volumes found"
    for vol in $VOLUMES; do
        docker volume rm "$vol" >/dev/null 2>&1
        if docker volume inspect "$vol" >/dev/null 2>&1; then left "volume $vol"; else removed "volume $vol"; fi
    done
    echo-return
else
    KEPT_VOLUMES="$VOLUMES"
fi

# --- 4. Images -------------------------------------------------------------------------
# The images the removed containers ran, plus the services' images from the
# compose file (some may have no container). Only those: never a prune. One a
# non-Zeltro container still uses is kept and reported, which is not a failure.
KEPT_IMAGES=""
if [ "$DELETE_IMAGES" = "1" ]; then
    echo-cyan "Removing Zeltro images ..."
    COMPOSE_IMAGES=""
    if [ -f "$R/etc/zeltro-cli/docker-compose.yaml" ]; then
        COMPOSE_IMAGES=$(cd "$R/etc/zeltro-cli" && docker compose --env-file "$R/etc/zeltro-cli/.env" config --images 2>/dev/null || true)
    fi
    ALL_IMAGES=$(printf '%s\n' ${IMAGES[@]+"${IMAGES[@]}"} $COMPOSE_IMAGES | grep -v '^$' | sort -u)
    found=0
    for img in $ALL_IMAGES; do
        docker image inspect "$img" >/dev/null 2>&1 || continue
        found=1
        users=$(docker ps -a --filter "ancestor=$img" --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')
        if [ -n "${users// /}" ]; then
            KEPT_IMAGES="$KEPT_IMAGES${KEPT_IMAGES:+, }$img (in use by ${users% })"
            echo-white "  kept image $img, in use by ${users% }"
            continue
        fi
        docker rmi "$img" >/dev/null 2>&1
        if docker image inspect "$img" >/dev/null 2>&1; then left "image $img"; else removed "image $img"; fi
    done
    [ "$found" = "1" ] || echo-white "  no Zeltro images found"
    echo-return
fi

# --- 5. Everything else Zeltro put on this machine (--purge) ------------------------------
# All of it except the projects folder. The data volumes went above: a
# reinstall would otherwise reuse zeltro-cli_mysql_data, and MariaDB would
# reject the new install's root password. Shared packages the installer may
# have added (Docker, Node, git) aren't Zeltro's and stay. Literal paths only.
if [ "$PURGE" = "1" ]; then
    echo-cyan "Removing the Zeltro app and configuration ..."
    remove_package zeltro-gui
    remove_path "$R/Applications/Zeltro.app" root
    for f in "$R/etc/zeltro-cli" \
             "$R/etc/apt/sources.list.d/zeltro.list" "$R/etc/apt/keyrings/zeltro.asc" \
             "$R/etc/yum.repos.d/zeltro.repo" "$R/etc/pki/rpm-gpg/RPM-GPG-KEY-zeltro" \
             "$R/etc/bash_completion.d/zeltro" "$R/usr/share/bash-completion/completions/zeltro" \
             "$R/usr/local/etc/bash_completion.d/zeltro" "$R/opt/homebrew/etc/bash_completion.d/zeltro" \
             "$R"/var/lib/apt/lists/packages.zeltro.ai_* "$R"/var/lib/apt/lists/packages.zeltro.build_*; do
        remove_path "$f" root
    done
    # The app's updater downloads into the temp folder (a 100 MB package was
    # found left behind).
    for f in "$R${TMPDIR:-/tmp}"/zeltro-update-* "$R/tmp"/zeltro-update-*; do
        remove_path "$f"
    done
    if [ -n "${HOME:-}" ]; then
        for d in "$HOME/.config/zeltro-gui" "$HOME/Library/Application Support/zeltro-gui" \
                 "$HOME/.zeltro" "$HOME/.cache/zeltro"; do
            remove_path "$d"
        done
        # The browser opener Zeltro adds inside WSL (zeltro_wsl_browser_shim).
        grep -q "Zeltro WSL browser opener" "$HOME/.local/bin/xdg-open" 2>/dev/null && remove_path "$HOME/.local/bin/xdg-open"
    fi
    echo-return
fi

# --- 6. The CLI itself ------------------------------------------------------------------
# A script install lives in /usr/local (share/zeltro-cli may be a symlink to a
# development checkout; only the link goes). A package install belongs to the
# package manager, so say how to remove it instead.
echo-cyan "Removing the Zeltro CLI ..."
CLI_PACKAGE_NOTE=""
for f in "$R/usr/local/bin/zeltro" "$R/usr/local/share/zeltro-cli"; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -d "$f" ] && [ ! -L "$f" ]; then as_root rm -rf "$f" 2>/dev/null; else as_root rm -f "$f" 2>/dev/null; fi
    if [ -e "$f" ] || [ -L "$f" ]; then left "$f"; else removed "$f"; fi
done
if [ "$PURGE" = "1" ]; then
    remove_package zeltro-cli
fi
if [ -d "$R/opt/zeltro-cli" ]; then
    if command -v dpkg >/dev/null 2>&1 && dpkg -s zeltro-cli >/dev/null 2>&1; then
        CLI_PACKAGE_NOTE="The zeltro-cli package is still installed. Remove it with: sudo apt remove zeltro-cli"
    else
        CLI_PACKAGE_NOTE="/opt/zeltro-cli is managed by your package manager. Remove the zeltro-cli package to finish."
    fi
    echo-white "  $CLI_PACKAGE_NOTE"
fi
echo-return

# --- Report -----------------------------------------------------------------------------------
STATUS="success"
[ ${#LEFT[@]} -eq 0 ] || STATUS="incomplete"

if [[ "$JSON_OUTPUT" == "1" ]]; then
    ZELTRO_UNINSTALL_STATUS="$STATUS" \
    ZELTRO_UNINSTALL_REMOVED="$(printf '%s\n' ${REMOVED[@]+"${REMOVED[@]}"})" \
    ZELTRO_UNINSTALL_LEFT="$(printf '%s\n' ${LEFT[@]+"${LEFT[@]}"})" \
    ZELTRO_UNINSTALL_KEPT_VOLUMES="$KEPT_VOLUMES" \
    ZELTRO_UNINSTALL_KEPT_IMAGES="$KEPT_IMAGES" \
    ZELTRO_UNINSTALL_NOTE="$CLI_PACKAGE_NOTE" \
    python3 -c '
import json, os
lines = lambda k: [l for l in os.environ.get(k, "").splitlines() if l]
print(json.dumps({"action": "uninstall", "status": os.environ["ZELTRO_UNINSTALL_STATUS"],
                  "removed": lines("ZELTRO_UNINSTALL_REMOVED"), "left": lines("ZELTRO_UNINSTALL_LEFT"),
                  "kept_volumes": lines("ZELTRO_UNINSTALL_KEPT_VOLUMES"),
                  "kept_images": [i for i in os.environ.get("ZELTRO_UNINSTALL_KEPT_IMAGES", "").split(", ") if i],
                  "note": os.environ.get("ZELTRO_UNINSTALL_NOTE", "")}))'
else
    echo-cyan "Summary"
    echo-white "  Removed: ${#REMOVED[@]} item(s), listed above."
    if [ -n "$KEPT_VOLUMES" ]; then
        echo-white "  Kept data volumes (remove with --delete-data): $(echo $KEPT_VOLUMES)"
    fi
    [ "$DELETE_IMAGES" = "1" ] || echo-white "  Kept Docker images (remove with --delete-images)."
    [ -z "$KEPT_IMAGES" ] || echo-white "  Kept images other containers use: $KEPT_IMAGES"
    [ "$PURGE" = "1" ] || echo-white "  Kept /etc/zeltro-cli and the app's settings (remove with --purge)."
    [ -n "$PROJECTS_DIR" ] && echo-white "  Your projects folder was not touched: $PROJECTS_DIR"
    if [ ${#LEFT[@]} -gt 0 ]; then
        echo-return
        echo-red "Not everything could be removed:"
        for l in "${LEFT[@]}"; do echo-red "  - $l"; done
    else
        echo-green "Zeltro was uninstalled."
    fi
fi

[ "$STATUS" = "success" ]
