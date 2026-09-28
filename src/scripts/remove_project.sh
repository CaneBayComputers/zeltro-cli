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
    echo-white "  --force-db-delete        Delete its databases, database users and named volumes"
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

# Work out which shared databases and users this project uses, BEFORE the
# directory is trashed -- the answer is in its files.
#
# This used to assume one database named after the project (t-freescout ->
# t_freescout) in one engine. Installers name theirs after the app (freescout,
# mastodon_production) and some create a dedicated user as well, so the real
# database and the user both survived `--force-db-delete`, and the next install
# of the same app met a stale schema or a user with a different password.
# project_db_refs.py reads the project's compose/env/config files, the
# installer recorded in its x-metadata, and every OTHER project's files, and
# reports which names are this project's alone ("db"/"user") and which another
# project also refers to ("shared-db"/"shared-user"), which are never dropped.
DB_NAME=$(echo "$PROJECT_NAME" | sed 's/-/_/g')
DB_REFS=""
if [ -d "$PROJECT_DIR" ]; then
    DB_REFS=$(ZELTRO_MARIADB="$(zeltro_service_container mariadb)" \
              ZELTRO_POSTGRES="$(zeltro_service_container postgres)" \
              ZELTRO_MONGO="$(zeltro_service_container mongo)" \
              python3 "$DEV_DIR/scripts/project_db_refs.py" "$PROJECTS_DIR_PATH" "$PROJECT_NAME" "$DEV_DIR/installers" 2>/dev/null) || DB_REFS=""
fi
_refs() { printf '%s\n' "$DB_REFS" | awk -v k="$1" '$1 == k { print $2 }'; }
DB_ENGINES="$(_refs engine | tr '\n' ' ')"
DB_CANDIDATES="$(_refs db | tr '\n' ' ')"
USER_CANDIDATES="$(_refs user | tr '\n' ' ')"
SHARED_DBS="$(_refs shared-db | tr '\n' ' ')"
SHARED_USERS="$(_refs shared-user | tr '\n' ' ')"

# A project only uses a shared Zeltro DB if its config references one of the
# shared database containers. Bundled-DB projects (e.g. budibase) don't, so the
# start-services + DROP step is skipped entirely for those.
HAS_SHARED_DB=false
[ -n "${DB_ENGINES// /}" ] && HAS_SHARED_DB=true
debug "Shared DB engines: $DB_ENGINES databases: $DB_CANDIDATES users: $USER_CANDIDATES shared: $SHARED_DBS $SHARED_USERS"

# No interactive confirmation. The database is PRESERVED by default and only
# dropped when --force-db-delete is passed (non-destructive default).
if [[ "$JSON_OUTPUT" != "1" ]]; then
    echo-cyan "This will remove the project '$PROJECT_NAME' and associated settings."
    echo-cyan "Project files will be moved to trash (recoverable)."
    if [ "$HAS_SHARED_DB" = true ] && [ "$FORCE_DB_DELETE" = false ] && [ "$PRESERVE_DATABASE" = false ]; then
        echo-yellow "Its database(s) will be PRESERVED — pass --force-db-delete to drop them."
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

# 5. Drop the project's databases and users (only with --force-db-delete).
DELETE_DB_CONFIRM="n"
_db_list_text="${DB_CANDIDATES% }"
[ -n "$_db_list_text" ] || _db_list_text="$DB_NAME"

if [ "$PRESERVE_DATABASE" = true ]; then
    echo-cyan "Preserving database(s) $_db_list_text (--preserve-database)."
    echo-white
elif [ "$HAS_SHARED_DB" = false ]; then
    debug "Project has no shared Zeltro DB hostnames — skipping database step"
    echo-cyan "Project '$PROJECT_NAME' does not use a Zeltro shared database (bundled DB or none). Skipping database step."
    echo-white
elif [ "$FORCE_DB_DELETE" = true ]; then
    echo-cyan "Deleting the project's databases and users (--force-db-delete)..."
    echo-white
    DELETE_DB_CONFIRM="y"
else
    echo-cyan "Preserving database(s) $_db_list_text (default). Pass --force-db-delete to drop them."
    echo-white
fi

DROPPED_DBS=""
DROPPED_USERS=""
if [[ "$DELETE_DB_CONFIRM" == "y" ]]; then

    # Make sure the engine is up long enough to drop from. A stopped shared
    # container is started, but a service is never ENABLED here: a machine that
    # has no Postgres container has no Postgres database to drop.
    _engine_ready() {
        local c="$1" kind="$2" i
        docker container inspect "$c" >/dev/null 2>&1 || return 1
        docker start "$c" >/dev/null 2>&1 || true
        for i in $(seq 1 30); do
            case "$kind" in
                postgres) docker container exec "$c" pg_isready -U root >/dev/null 2>&1 && return 0 ;;
                mariadb)  docker container exec "$c" mariadb -u root -e "SELECT 1" >/dev/null 2>&1 && return 0 ;;
                mongo)    docker container exec "$c" mongosh --quiet --eval "1" >/dev/null 2>&1 && return 0 ;;
            esac
            sleep 1
        done
        return 1
    }

    _in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

    for _db in $SHARED_DBS; do
        echo-yellow "Keeping database '$_db': another project also uses it."
    done
    for _u in $SHARED_USERS; do
        echo-yellow "Keeping database user '$_u': another project also uses it."
    done

    _pg="$(zeltro_service_container postgres)"
    _my="$(zeltro_service_container mariadb)"
    _mongo="$(zeltro_service_container mongo)"

    for _engine in $DB_ENGINES; do
        case "$_engine" in
            postgres)
                if ! _engine_ready "$_pg" postgres; then
                    echo-yellow "Shared postgres container '$_pg' is not available; its databases were not checked."
                    continue
                fi
                _existing_dbs=$(docker container exec -e PGPASSWORD=password "$_pg" psql -U root -d postgres -tAc "SELECT datname FROM pg_database;" 2>/dev/null | tr '\n' ' ' || true)
                _existing_users=$(docker container exec -e PGPASSWORD=password "$_pg" psql -U root -d postgres -tAc "SELECT rolname FROM pg_roles WHERE NOT rolsuper;" 2>/dev/null | tr '\n' ' ' || true)
                for _db in $DB_CANDIDATES; do
                    _in_list "$_db" "$_existing_dbs" || continue
                    if docker container exec -e PGPASSWORD=password "$_pg" psql -U root -d postgres -c "DROP DATABASE \"$_db\" WITH (FORCE);" >/dev/null 2>&1 \
                        || docker container exec -e PGPASSWORD=password "$_pg" psql -U root -d postgres -c "DROP DATABASE \"$_db\";" >/dev/null 2>&1; then
                        echo-green "Database '$_db' deleted from PostgreSQL."
                        DROPPED_DBS="$DROPPED_DBS $_db"
                    else
                        echo-yellow "Could not delete PostgreSQL database '$_db'."
                    fi
                done
                for _u in $USER_CANDIDATES; do
                    _in_list "$_u" "$_existing_users" || continue
                    if docker container exec -e PGPASSWORD=password "$_pg" psql -U root -d postgres -c "DROP ROLE \"$_u\";" >/dev/null 2>&1; then
                        echo-green "PostgreSQL role '$_u' deleted."
                        DROPPED_USERS="$DROPPED_USERS $_u"
                    else
                        echo-yellow "Could not delete PostgreSQL role '$_u' (it may still own objects elsewhere)."
                    fi
                done
                ;;
            mongo)
                if ! _engine_ready "$_mongo" mongo; then
                    echo-yellow "Shared mongo container '$_mongo' is not available; its databases were not checked."
                    continue
                fi
                _existing_dbs=$(docker container exec "$_mongo" mongosh --quiet -u root -p password --authenticationDatabase admin --eval "db.getMongo().getDBNames().join(' ')" 2>/dev/null \
                    || docker container exec "$_mongo" mongosh --quiet --eval "db.getMongo().getDBNames().join(' ')" 2>/dev/null || true)
                for _db in $DB_CANDIDATES; do
                    _in_list "$_db" "$_existing_dbs" || continue
                    if docker container exec "$_mongo" mongosh --quiet -u root -p password --authenticationDatabase admin --eval "db.getSiblingDB('$_db').dropDatabase();" >/dev/null 2>&1 \
                        || docker container exec "$_mongo" mongosh --quiet --eval "db.getSiblingDB('$_db').dropDatabase();" >/dev/null 2>&1; then
                        echo-green "Database '$_db' deleted from MongoDB."
                        DROPPED_DBS="$DROPPED_DBS $_db"
                    else
                        echo-yellow "Could not delete MongoDB database '$_db'."
                    fi
                done
                ;;
            mariadb)
                if ! _engine_ready "$_my" mariadb; then
                    echo-yellow "Shared mariadb container '$_my' is not available; its databases were not checked."
                    continue
                fi
                _existing_dbs=$(docker container exec "$_my" mariadb -u root -N -e "SHOW DATABASES;" 2>/dev/null | tr '\n' ' ' || true)
                for _db in $DB_CANDIDATES; do
                    _in_list "$_db" "$_existing_dbs" || continue
                    if docker container exec "$_my" mariadb -u root -e "DROP DATABASE \`$_db\`;" >/dev/null 2>&1; then
                        echo-green "Database '$_db' deleted from MariaDB."
                        DROPPED_DBS="$DROPPED_DBS $_db"
                    else
                        echo-yellow "Could not delete MariaDB database '$_db'."
                    fi
                done
                for _u in $USER_CANDIDATES; do
                    # A user exists once per host it may connect from ('x'@'%',
                    # 'x'@'localhost'); drop every one of them.
                    _hosts=$(docker container exec "$_my" mariadb -u root -N -e "SELECT host FROM mysql.user WHERE user='$_u';" 2>/dev/null || true)
                    [ -n "$_hosts" ] || continue
                    _ok=1
                    while IFS= read -r _h; do
                        [ -n "$_h" ] || continue
                        docker container exec "$_my" mariadb -u root -e "DROP USER '$_u'@'$_h';" >/dev/null 2>&1 || _ok=0
                    done <<< "$_hosts"
                    if [ "$_ok" = 1 ]; then
                        echo-green "MariaDB user '$_u' deleted."
                        DROPPED_USERS="$DROPPED_USERS $_u"
                    else
                        echo-yellow "Could not delete every host entry of MariaDB user '$_u'."
                    fi
                done
                ;;
        esac
    done

    if [ -z "$DROPPED_DBS" ] && [ -z "$DROPPED_USERS" ]; then
        echo-yellow "No database or user of '$PROJECT_NAME' was found to delete."
    fi
    echo-white

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
