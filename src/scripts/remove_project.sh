#!/bin/bash

set -e

# Set up directories and aliases
ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)
source scripts/pre_check.sh

echo-return; echo-return

# Usage function to explain the script
usage() {
    echo-white "Usage: ${ZELTRO_CMD:-$0} [project_name] [options]"
    echo-white "Removes a project and associated settings"
    echo-white ""
    echo-white ""
    echo-white "By default:"
    echo-white "  • Project files are moved to trash (recoverable)"
    echo-white "  • The database and the project's Docker volumes are PRESERVED"
    echo-white "    (pass --force-db-delete to drop both)"
    echo-white ""
    echo-white "Options:"
    echo-white "  --force-db-delete        Delete the database AND the project's named volumes"
    echo-white "  --preserve-database      Skip database deletion entirely"
    echo-white "  --json-output            Output results in JSON format"
    echo-white "  --debug                  Enable debug logging"
    echo-white "  --no-colors              Disable colored output"
    echo-white ""
    echo-white "Examples:"
    echo-white "  ${ZELTRO_CMD:-$0} my-project                     # Remove project, keep the database"
    echo-white "  ${ZELTRO_CMD:-$0} my-project --force-db-delete   # Remove project and database without prompting"
    echo-white "  ${ZELTRO_CMD:-$0} my-project --preserve-database # Remove project, keep database"
    echo-white "  ${ZELTRO_CMD:-$0} my-project --json-output       # Remove with JSON output"
}

# Initialize variables
PROJECT_NAME=""
FORCE_TRASH_PROJECT=false
FORCE_DB_DELETE=false
PRESERVE_DATABASE=false
JSON_OUTPUT="${JSON_OUTPUT:-}"
NO_COLOR="${NO_COLOR:-}"

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force-db-delete)
            FORCE_DB_DELETE=true
            shift
            ;;
        --preserve-database)
            PRESERVE_DATABASE=true
            shift
            ;;
        --force)
            # DESTRUCTIVE legacy alias for --force-db-delete. It once meant "skip
            # the confirmation prompts"; those prompts no longer exist, so its
            # only surviving effect is dropping the database. Kept for backward
            # compatibility and deliberately undocumented — anything carrying it
            # forward from the old contract would silently invert the
            # preserve-by-default behaviour. --preserve-database still wins.
            FORCE_DB_DELETE=true
            shift
            ;;
        --json-output)
            JSON_OUTPUT=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --no-colors)
            NO_COLOR=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            echo-red "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            else
                echo-red "Too many arguments"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Initialize debug logging
debug "Script started: remove_project.sh with args: $ORIGINAL_ARGS"

# A project name is required — no interactive picker.
if [ -z "$PROJECT_NAME" ]; then
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        debug "No project name provided in JSON mode"
    fi
    echo-red "No project specified."
    echo-white "Usage: zeltro remove <project> [--force-db-delete] [--preserve-database]"
    exit 1
fi

PROJECT_DIR="$PROJECTS_DIR_PATH/$PROJECT_NAME"
# No /etc/hosts cleanup: Zeltro does not write that file any more.

debug "Project directory: $PROJECT_DIR"
debug "Force trash project: $FORCE_TRASH_PROJECT"
debug "Force DB delete: $FORCE_DB_DELETE"
debug "JSON output mode: $JSON_OUTPUT"

# Detect database engine from project config before we trash the directory.
# Check root .env first, then fall back to scanning all env files and docker-compose.yaml
# (complex projects with adapted composes often have no root .env).
DB_ENGINE="mysql"
HAS_SHARED_DB=false
_DB_HINTS=""
if [ -f "$PROJECT_DIR/.env" ]; then
    _DB_HINTS=$(grep -E "^(DB_HOST|DB_CONNECTION)=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d ' ' | tr '\n' ' ')
fi
if [ -z "$_DB_HINTS" ]; then
    # No root .env or no DB_HOST/DB_CONNECTION in it — scan env files (the root
    # .env too: installers like langfuse and plane name the host in DATABASE_URL or
    # PGHOST there) and docker-compose.yaml for Zeltro shared service hostnames
    _DB_HINTS=$(grep -rhE "(zeltro|podium)-(postgres|mongo|mariadb)" \
        "$PROJECT_DIR"/.env "$PROJECT_DIR"/*.env "$PROJECT_DIR"/.env.* "$PROJECT_DIR"/env/ \
        "$PROJECT_DIR"/docker-compose.yaml "$PROJECT_DIR"/docker-compose.yml \
        2>/dev/null | head -5 | tr '\n' ' ')
fi
if echo "$_DB_HINTS" | grep -qiE "postgres|pgsql|postgresql"; then
    DB_ENGINE="postgres"
elif echo "$_DB_HINTS" | grep -qiE "mongo"; then
    DB_ENGINE="mongo"
fi

# A project only uses a shared Zeltro DB if its config references one of the
# zeltro-* hostnames (podium-* on a box installed before the rename). Bundled-DB
# projects (e.g. budibase) don't, so we should
# skip the start-services + DROP DATABASE step entirely for those.
if echo "$_DB_HINTS" | grep -qE "(zeltro|podium)-(postgres|mongo|mariadb)"; then
    HAS_SHARED_DB=true
fi
debug "Detected database engine: $DB_ENGINE, uses shared DB: $HAS_SHARED_DB"

# No interactive confirmation. The database is PRESERVED by default and only
# dropped when --force-db-delete is passed (non-destructive default).
if [[ "$JSON_OUTPUT" != "1" ]]; then
    echo-cyan "This will remove the project '$PROJECT_NAME' and associated settings."
    echo-cyan "Project files will be moved to trash (recoverable)."
    if [ "$HAS_SHARED_DB" = true ] && [ "$FORCE_DB_DELETE" = false ] && [ "$PRESERVE_DATABASE" = false ]; then
        echo-yellow "The shared database '$DB_ENGINE' will be PRESERVED — pass --force-db-delete to drop it."
    fi
    echo-white
fi

debug "Starting project removal for: $PROJECT_NAME"
echo-cyan "Removing project '$PROJECT_NAME'..."

# 1. Run shutdown.sh to stop the project and remove iptables rules
debug "Starting step 1: Shutting down project"
echo-return
echo-cyan "Shutting down project '$PROJECT_NAME'..."
echo-white
# Treat a non-running or already-removed project as a non-fatal condition
if ! "$DEV_DIR/scripts/shutdown.sh" "$PROJECT_NAME"; then
    debug "shutdown.sh returned non-zero for project '$PROJECT_NAME' (likely not running); continuing removal"
    echo-yellow "Project '$PROJECT_NAME' is not running or could not be shut down. Continuing removal."
    echo-white
fi

# 1b. Remove the project's named volumes when --force-db-delete was passed.
#
# Reported by the GUI session and reproduced on two apps: dropping the database
# while leaving the volumes produces an app that believes it is already installed
# (moodle's config.php, glpi's data dir) pointed at an empty schema. The next
# install crash-loops, and reinstalling cannot fix it because the contradiction
# survives every attempt -- the same trap as the stale DB user, where the obvious
# remedy cannot touch the cause.
#
# --force-db-delete already means "destroy this project's data", so the volumes
# belong in that promise. Plain `zeltro remove` still keeps them, matching the
# fact that it keeps the database.
#
# Must run BEFORE the directory is trashed: compose needs its own file to know
# which volumes are its.
if [ "$FORCE_DB_DELETE" = true ] && [ -f "$PROJECT_DIR/docker-compose.yaml" ]; then
    debug "Starting step 1b: removing named volumes (--force-db-delete)"
    _vols=$( (cd "$PROJECT_DIR" && docker compose config --volumes 2>/dev/null) )
    if [ -n "$_vols" ]; then
        echo-cyan "Removing project volumes (--force-db-delete)..."
        (cd "$PROJECT_DIR" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
        # compose down -v only removes volumes it still tracks; sweep any that
        # outlived it under the standard <project>_<volume> naming.
        for _v in $_vols; do
            docker volume rm "${PROJECT_NAME}_${_v}" >/dev/null 2>&1 || true
        done
        _left=$(docker volume ls -q --filter "name=^${PROJECT_NAME}_" 2>/dev/null | wc -l)
        if [ "$_left" -eq 0 ]; then
            echo-green "Project volumes removed."
        else
            echo-yellow "$_left project volume(s) could not be removed - remove by hand or the next install may misbehave:"
            docker volume ls -q --filter "name=^${PROJECT_NAME}_" 2>/dev/null | sed 's/^/    /'
        fi
        echo-white
    fi
fi

# 2. Move Project Directory to Trash  
debug "Starting step 2: Moving project directory to trash"
echo-cyan "Moving project directory to trash..."
echo-white
if [ -d "$PROJECT_DIR" ]; then
    # If a previous removal already trashed a project with this name, trash-put
    # refuses to overwrite. Rename to a timestamped path first so the trash
    # entry is unique and the move always succeeds.
    TRASH_TARGET="$PROJECT_DIR"
    if command -v trash-put &> /dev/null || command -v trash &> /dev/null; then
        if [ -e "$HOME/.local/share/Trash/files/$(basename "$PROJECT_DIR")" ]; then
            TRASH_TARGET="${PROJECT_DIR}.$(date +%Y%m%d-%H%M%S)"
            mv "$PROJECT_DIR" "$TRASH_TARGET"
            debug "Renamed project dir to $TRASH_TARGET to avoid trash collision"
        fi
    fi
    # Function to move project to trash safely
    if command -v trash-put &> /dev/null; then
        trash-put "$TRASH_TARGET"
        echo-green "Project directory moved to trash (can be recovered)."
    elif command -v trash &> /dev/null; then
        # Alternative trash command (some systems)
        trash "$TRASH_TARGET"
        echo-green "Project directory moved to trash (can be recovered)."
    else
        # No trash tool available. Non-destructive default: do NOT permanently
        # delete without consent — leave the directory in place and tell the user.
        echo-yellow "trash-cli not installed — leaving the project directory in place to avoid permanent deletion."
        echo-white "Install trash-cli, or remove the directory manually:"
        echo-white "  Ubuntu/Debian: sudo apt-get install trash-cli"
        echo-white "  Arch Linux:    sudo pacman -S trash-cli"
        echo-white "  Fedora/RHEL:   sudo dnf install trash-cli"
        echo-white "  macOS:         brew install trash-cli"
        echo-white "  Manual:        rm -rf \"$PROJECT_DIR\""
        echo-white
    fi
    echo-white
else
    echo-yellow "Project directory not found. Skipping directory removal."
    echo-white
fi

# 3. (was: remove the /etc/hosts entry)
#
# Nothing to do. Zeltro no longer writes /etc/hosts, so there is no entry to
# clean up. Installs that predate this may still have stale entries; they are
# harmless — the name simply resolves to an address with nothing behind it —
# and removing them would need the sudo this change exists to avoid.

# 4. Delete Docker Container
debug "Starting step 4: Deleting Docker container"
echo-cyan "Attempting to delete Docker container for '$PROJECT_NAME'..."
echo-white
if docker rm "$PROJECT_NAME" --force >/dev/null 2>&1; then
    echo-green "Docker container for '$PROJECT_NAME' removed."
    echo-white
else
    echo-yellow "Docker container for '$PROJECT_NAME' not found or already removed."
    echo-white
fi

# 5. Ask if user wants to delete the associated database
DB_NAME=$(echo "$PROJECT_NAME" | sed 's/-/_/g')
DELETE_DB_CONFIRM="n"

# Database is preserved by default; only dropped with --force-db-delete.
if [ "$PRESERVE_DATABASE" = true ]; then
    echo-cyan "Preserving database '$DB_NAME' (--preserve-database)."
    echo-white
    DELETE_DB_CONFIRM="n"
elif [ "$HAS_SHARED_DB" = false ]; then
    debug "Project has no shared Zeltro DB hostnames — skipping database step"
    echo-cyan "Project '$PROJECT_NAME' does not use a Zeltro shared database (bundled DB or none). Skipping database step."
    echo-white
    DELETE_DB_CONFIRM="n"
elif [ "$FORCE_DB_DELETE" = true ]; then
    echo-cyan "Deleting database '$DB_NAME' (--force-db-delete)..."
    DELETE_DB_CONFIRM="y"
else
    echo-cyan "Preserving database '$DB_NAME' (default). Pass --force-db-delete to drop it."
    echo-white
    DELETE_DB_CONFIRM="n"
fi

if [[ "$DELETE_DB_CONFIRM" == "y" ]]; then

    # Start services
    "$DEV_DIR/scripts/start_services.sh"

    # Check if db exists
    echo-cyan "Checking if database '$DB_NAME' exists in $DB_ENGINE..."
    echo-white

    case "$DB_ENGINE" in
        postgres)
            DB_EXISTS=$(docker container exec -e PGPASSWORD=password "$POSTGRES_CONTAINER_NAME" psql -U root -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>/dev/null || true)
            if [ -n "$DB_EXISTS" ]; then
                echo-cyan "Deleting database '$DB_NAME' from PostgreSQL..."
                echo-white
                docker container exec -e PGPASSWORD=password "$POSTGRES_CONTAINER_NAME" psql -U root -d postgres -c "DROP DATABASE \"$DB_NAME\";" >/dev/null 2>&1 \
                    && echo-green "Database '$DB_NAME' deleted." \
                    || echo-yellow "Database deletion failed."
                echo-white
            else
                echo-yellow "Database '$DB_NAME' not found in PostgreSQL. Skipping deletion."
                echo-white
            fi
            ;;
        mongo)
            DB_EXISTS=$(docker container exec "$MONGO_CONTAINER_NAME" mongosh --quiet --eval "db.getMongo().getDBNames().indexOf('$DB_NAME') >= 0 ? '1' : ''" 2>/dev/null || true)
            if [ "$DB_EXISTS" = "1" ]; then
                echo-cyan "Deleting database '$DB_NAME' from MongoDB..."
                echo-white
                docker container exec "$MONGO_CONTAINER_NAME" mongosh --quiet --eval "db.getSiblingDB('$DB_NAME').dropDatabase();" >/dev/null 2>&1 \
                    && echo-green "Database '$DB_NAME' deleted." \
                    || echo-yellow "Database deletion failed."
                echo-white
            else
                echo-yellow "Database '$DB_NAME' not found in MongoDB. Skipping deletion."
                echo-white
            fi
            ;;
        *)
            DB_EXISTS=$(docker container exec "$MARIADB_CONTAINER_NAME" mariadb -u root -e "SHOW DATABASES LIKE '$DB_NAME';" 2>/dev/null | grep "$DB_NAME" || true)
            if [ -n "$DB_EXISTS" ]; then
                echo-cyan "Deleting database '$DB_NAME' from MariaDB..."
                echo-white
                json-mysql -u root -e "DROP DATABASE \`$DB_NAME\`;" && echo-green "Database '$DB_NAME' deleted." || echo-yellow "Database deletion failed."
                echo-white
            else
                echo-yellow "Database '$DB_NAME' not found in MariaDB. Skipping deletion."
                echo-white
            fi
            ;;
    esac

else
    echo-yellow "Database deletion skipped."
    echo-white
fi

# Return to original directory
cd "$ORIG_DIR"

# JSON output for project removal
if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "{\"action\": \"remove_project\", \"project_name\": \"$PROJECT_NAME\", \"database_deleted\": $([ "$DELETE_DB_CONFIRM" = "y" ] && echo "true" || echo "false"), \"status\": \"success\"}"
else
    echo-green "Project '$PROJECT_NAME' and associated settings have been removed."
    echo-white
fi
