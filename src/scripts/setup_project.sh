#!/bin/bash

set -e


ORIG_DIR=$(pwd)

# Get the directory of this script, handling both direct execution and sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
else
    # Script is being executed directly
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
fi

cd "$SCRIPT_DIR/.."

DEV_DIR=$(pwd)

# Pre check to make sure development is installed (also sources functions.sh and .env)
source "$DEV_DIR/scripts/pre_check.sh"


# Function to display usage
usage() {
    echo-white "Usage: ${ZELTRO_CMD:-$0} [project_name] [database_engine] [options]"
    echo-white "Sets up a project in the projects directory"
    echo-white ""
    echo-white "With no project name, shows an interactive picker (skipped in --json-output mode)."
    echo-white ""
    echo-white "Arguments:"
    echo-white "  project_name     Name of the project to setup"
    echo-white "  database_engine  Database type: mysql, postgres, mongo, sqlite (default: mysql)"
    echo-white ""
    echo-white "Options:"
    echo-white "  --json-output           Output JSON responses (for programmatic use)"
    echo-white "  --no-colors             Disable colored output"
    echo-white "  --debug                 Enable debug logging to /tmp/zeltro-cli-debug.log"
    echo-white "  --overwrite-docker-compose  Overwrite existing docker-compose.yaml without prompting"
    echo-white "  --framework FRAMEWORK   Force specific framework (laravel, kavera, octobercms, drupal, wordpress, php, fastapi, flask, django, python, express, nestjs, fastify, node, nextjs, nuxt, sveltekit, astro, hono, react, vue)"
    echo-white "  --db-name NAME          Database name (default: project name with dashes as underscores)"
    echo-white "  --image REF             Override the project's Docker image (default: framework cbc base image)"
    echo-white "  --overwrite-env         Regenerate the project's .env even if one already exists"
    echo-white "  --no-migration          Skip database migrations (they run by default)"
    echo-white "  --no-storage-symlink    Skip creating public/storage symlink (Laravel only)"
    echo-white ""
    echo-white "Examples:"
    echo-white "  ${ZELTRO_CMD:-$0} my-project mysql"
    echo-white "  ${ZELTRO_CMD:-$0} my-project postgres --json-output"
}


# Initialize variables
PROJECT_NAME=""
DATABASE_ENGINE="mariadb"
OVERWRITE_DOCKER_COMPOSE=""
SKIP_STORAGE_SYMLINK=false
NO_STARTUP=0
DB_NAME_OVERRIDE=""
CUSTOM_IMAGE=""
OVERWRITE_ENV=0
RUN_MIGRATIONS=1
MIGRATE_SAFE=0
JSON_OUTPUT="${JSON_OUTPUT:-}"
NO_COLOR="${NO_COLOR:-}"

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --json-output)
            JSON_OUTPUT=1
            shift
            ;;
        --no-colors)
            NO_COLOR=1
            shift
            ;;
        --overwrite-docker-compose)
            OVERWRITE_DOCKER_COMPOSE=1
            shift
            ;;
        --framework)
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                FORCED_FRAMEWORK="$2"
                shift 2
            else
                error "Error: --framework requires a framework type (laravel, wordpress, php)"
            fi
            ;;
        --no-storage-symlink)
            SKIP_STORAGE_SYMLINK=true
            shift
            ;;
        --db-name)
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                DB_NAME_OVERRIDE="$2"
                shift 2
            else
                error "Error: --db-name requires a database name"
            fi
            ;;
        --image)
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                CUSTOM_IMAGE="$2"
                shift 2
            else
                error "Error: --image requires a Docker image reference (e.g. canebaycomputers/cbc:nginx-php8)"
            fi
            ;;
        --overwrite-env)
            OVERWRITE_ENV=1
            shift
            ;;
        --no-migration|--no-migrations)
            RUN_MIGRATIONS=0
            shift
            ;;
        --no-startup)
            NO_STARTUP=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1. Use --help for usage information"
            ;;
        *)
            # Collect positional arguments
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# A project name is required — no interactive picker.
if [ ${#POSITIONAL_ARGS[@]} -lt 1 ]; then
    error "Error: project name is required. Usage: zeltro setup <project> [database_engine] [options]"
fi
PROJECT_NAME="${POSITIONAL_ARGS[0]}"

if [ ${#POSITIONAL_ARGS[@]} -gt 1 ]; then
    DATABASE_ENGINE="${POSITIONAL_ARGS[1]}"
fi

# Initialize debug logging
debug "Script started: setup_project.sh with args: $ORIGINAL_ARGS"


# Use the configured projects directory
PROJECTS_DIR="$PROJECTS_DIR_PATH"
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"

# Cleanup state flags — set as operations complete so trap can undo them
_hosts_entry_added=0
_compose_file_created=0
_container_started=0

_setup_cleanup() {
    local code=$?
    [ $code -eq 0 ] && return
    echo-red "Setup failed — cleaning up partial state..."
    if [ "$_container_started" = "1" ] && [ -f "$PROJECT_DIR/docker-compose.yaml" ]; then
        (cd "$PROJECTS_DIR_PATH" && docker compose -f "$PROJECT_DIR/docker-compose.yaml" down --remove-orphans 2>/dev/null) || true
    fi
    if [ "$_hosts_entry_added" = "1" ]; then
        : # nothing to unwind — no /etc/hosts entry is written any more
    fi
    if [ "$_compose_file_created" = "1" ]; then
        rm -f "$PROJECT_DIR/docker-compose.yaml"
    fi
    # `zeltro new` sources this script, so our `trap ... ERR` above replaced its
    # handler. Call its cleanup explicitly or a failed setup leaves the
    # half-built directory it created behind. Not defined for a plain
    # `zeltro setup`, where the directory is the user's and must not be touched.
    if declare -F _remove_incomplete_project >/dev/null 2>&1; then
        _remove_incomplete_project
    fi
}
trap _setup_cleanup ERR

# Check for project folder existence
if ! [ -d "$PROJECT_DIR" ]; then
    error "Project folder does not exist!"
fi


# Bring up the database engine this project asked for. Services are profile-gated
# and nothing runs by default, so this is what makes `--database postgres` work on
# a machine that has never used Postgres. Framework projects only write the engine
# into .env later, so the declared engine is the earliest reliable signal.
ensure_services_for_engine "$DATABASE_ENGINE" || true

# Start micro services
if [[ "$JSON_OUTPUT" == "1" ]]; then
    START_SERVICES_OUTPUT=$(source "$DEV_DIR/scripts/start_services.sh" 2>&1)
    START_SERVICES_EXIT_CODE=$?
    if [ $START_SERVICES_EXIT_CODE -ne 0 ]; then
        echo "$START_SERVICES_OUTPUT"
        exit $START_SERVICES_EXIT_CODE
    fi
else
    source "$DEV_DIR/scripts/start_services.sh"
fi


# Only shutdown project if a docker-compose file already exists (existing project reconfiguration)
# For new projects, there's no need to shut down containers that don't exist yet
if [ -f "$PROJECT_DIR/docker-compose.yaml" ] || [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo-yellow "Existing project detected. Shutting down containers before reconfiguration..."
        # Run as a subprocess, NOT sourced.
        #
        # shutdown.sh sets `set -e` on line 3. Sourcing it therefore re-enables
        # errexit in THIS shell, which is why both earlier guards failed: the
        # `|| true` around the source did nothing on bash 3.2, and an explicit
        # `set +e` around it was simply overwritten by the sourced file's own
        # `set -e` before the failure happened.
        #
        # shutdown returns non-zero when the container is not running — the
        # normal case when re-running setup on an existing project — so on macOS
        # `zeltro setup <existing>` died with nothing but "Setup failed —
        # cleaning up partial state...". bash 4+ hid it, because there the
        # `|| true` suspension really did apply.
        #
        # A subprocess contains all of it: its set -e, its exits, its traps. The
        # dispatcher already invokes it exactly this way for `zeltro down`.
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            SHUTDOWN_OUTPUT=$("$DEV_DIR/scripts/shutdown.sh" "$PROJECT_NAME" 2>&1) || true
        else
            "$DEV_DIR/scripts/shutdown.sh" "$PROJECT_NAME" || true
        fi
else
    echo-green "New project detected. Skipping container shutdown."
fi


# Enter into project and get PHP version
cd "$PROJECT_DIR"

# Resolve FRAMEWORK if not already set (e.g. when setup_project.sh is called directly)
if [ -z "$FRAMEWORK" ]; then
    if [ -n "$FORCED_FRAMEWORK" ]; then
        FRAMEWORK="$FORCED_FRAMEWORK"
    elif [ -f "app.py" ] && grep -qiE '^[[:space:]]*(from|import)[[:space:]]+flask' app.py 2>/dev/null; then
        FRAMEWORK="flask"
    elif [ -f "main.py" ] && grep -qiE '^[[:space:]]*(from|import)[[:space:]]+flask' main.py 2>/dev/null; then
        # Flask app that happens to live in main.py — check before falling
        # through to the filename-only FastAPI match below.
        FRAMEWORK="flask"
    elif [ -f "main.py" ]; then
        FRAMEWORK="fastapi"
    elif [ -f "manage.py" ]; then
        FRAMEWORK="django"
    elif [ -f "wp-config-sample.php" ] || [ -f "wp-config.php" ]; then
        FRAMEWORK="wordpress"
    elif [ -f "composer.json" ] && grep -q '"drupal/core' composer.json 2>/dev/null; then
        # Matches drupal/core-recommended and drupal/core-composer-scaffold, so it
        # catches both Zeltro-scaffolded projects and cloned ones using the stock
        # web/ docroot. Checked before artisan because Drupal has no artisan and
        # would otherwise fall through to the plain-PHP default.
        FRAMEWORK="drupal"
    elif [ -d "web/core/lib/Drupal" ] || [ -d "public/core/lib/Drupal" ] || [ -f "core/lib/Drupal.php" ]; then
        # Already-built trees whose composer.json is absent or nonstandard.
        FRAMEWORK="drupal"
    elif [ -f "artisan" ]; then
        FRAMEWORK="laravel"
    elif [ -f "package.json" ] && [ ! -f "composer.json" ] && [ ! -f "artisan" ]; then
        # Order matters. Meta-frameworks are checked first because they carry
        # the lower-level packages as transitive dependencies — a Next.js
        # project lists react, a SvelteKit project lists vite, and matching on
        # those first would classify every one of them as a plain SPA.
        if grep -q '"@nestjs/core"' package.json 2>/dev/null; then
            FRAMEWORK="nestjs"
        elif grep -q '"next"[[:space:]]*:' package.json 2>/dev/null; then
            FRAMEWORK="nextjs"
        elif grep -q '"nuxt"[[:space:]]*:' package.json 2>/dev/null; then
            FRAMEWORK="nuxt"
        elif grep -q '"@sveltejs/kit"' package.json 2>/dev/null; then
            FRAMEWORK="sveltekit"
        elif grep -q '"astro"[[:space:]]*:' package.json 2>/dev/null; then
            FRAMEWORK="astro"
        elif grep -q '"hono"[[:space:]]*:' package.json 2>/dev/null; then
            FRAMEWORK="hono"
        elif grep -q '"fastify"' package.json 2>/dev/null; then
            FRAMEWORK="fastify"
        elif grep -q '"express"' package.json 2>/dev/null; then
            FRAMEWORK="express"
        elif grep -q '"@vitejs/plugin-react"' package.json 2>/dev/null; then
            FRAMEWORK="react"
        elif grep -q '"@vitejs/plugin-vue"' package.json 2>/dev/null; then
            FRAMEWORK="vue"
        else
            FRAMEWORK="node"
        fi
    else
        FRAMEWORK="php"
    fi
fi

# Load framework registry
source "$DEV_DIR/frameworks/${FRAMEWORK}.sh"

echo-return "$(pwd)"; echo-return

# Determine PHP version


# Convert dashes to underscores (used for the project's package/module name)
PROJECT_NAME_SNAKE=$(echo "$PROJECT_NAME" | sed 's/-/_/g')

# Database name: explicit --db-name override, otherwise the snake-cased project name.
# Kept separate from PROJECT_NAME_SNAKE so overriding the DB doesn't rename the
# Django settings module / package directory.
if [ -n "$DB_NAME_OVERRIDE" ]; then
    # Sanitize: allow letters, digits, and underscores only (valid across mysql/postgres)
    DB_NAME=$(echo "$DB_NAME_OVERRIDE" | sed 's/[^A-Za-z0-9_]/_/g')
    if [ "$DB_NAME" != "$DB_NAME_OVERRIDE" ]; then
        echo-yellow "Note: database name sanitized to '$DB_NAME' (only letters, digits, underscores allowed)."
    fi
else
    DB_NAME="$PROJECT_NAME_SNAKE"
fi
export DB_NAME


# Get a random D class number and make sure it doesn' already exist in hosts file
#
# Upper bound stops at 239: .250-.254 is reserved for optional shared services,
# with .240-.249 left as headroom. Shared services used to sit on low addresses
# and projects could be handed one, which surfaced as a shared service failing
# to start with "Address already in use" long after the project claimed the IP.
echo-return -n "Docker IP Address: "

while true; do

    D_CLASS=$((RANDOM % (239 - 100 + 1) + 100))

    IP_ADDRESS="$VPC_SUBNET.$D_CLASS"

    # Collision is checked against the project compose files, which are what
    # actually claim an address. /etc/hosts used to be consulted here, and a
    # stale entry left by a half-removed project made an address permanently
    # unusable while nothing was using it.
    if ! zeltro_ip_in_use "$IP_ADDRESS"; then break; fi

done

# No /etc/hosts write. The address is recorded in the project's own compose
# file, written below, which is the only thing that needs to know it.
#
# Writing it here was the sole reason creating a project required sudo, and
# that requirement cost far more than the feature returned: a piped installer
# had its password prompt eaten by the script on stdin, macOS tty_tickets made
# unattended runs impossible, and every remote caller had to solve an
# interactive auth problem just to create a project.
#
# The named host it bought never worked on macOS or Windows anyway — Docker
# keeps container IPs inside a VM on both — so it was a Linux-only convenience
# billed to every platform.

echo-return


# Check if a docker-compose file already exists and handle overwrite using reusable function
EXISTING_COMPOSE_FILE=""
if [ -f "docker-compose.yaml" ]; then
    EXISTING_COMPOSE_FILE="docker-compose.yaml"
elif [ -f "docker-compose.yml" ]; then
    EXISTING_COMPOSE_FILE="docker-compose.yml"
fi

# Adopting an existing project (it shipped its own compose) → use non-destructive
# migrations (apply pending only). Greenfield projects use the full reset+seed.
if [ -n "$EXISTING_COMPOSE_FILE" ]; then
    MIGRATE_SAFE=1
fi

# A .env that setup is going to KEEP is an existing app too, compose or not.
# `zeltro new` always passes --overwrite-env, so a kept .env never means
# greenfield. Without this, an app with a real .env but no compose file (most
# Laravel apps) was treated as greenfield and got `migrate:fresh` -- which drops
# every table -- run against whatever database that kept .env points at.
KEEP_EXISTING_ENV=0
if [ -f ".env" ] && [ "${OVERWRITE_ENV:-0}" != "1" ]; then
    KEEP_EXISTING_ENV=1
    MIGRATE_SAFE=1
fi
export MIGRATE_SAFE

# Capture original compose and detect complexity before conflict handling deletes it
ORIGINAL_COMPOSE_TMPFILE="/tmp/zeltro_original_compose_$$.yaml"
ORIGINAL_COMPOSE_IS_COMPLEX=0
if [ -n "$EXISTING_COMPOSE_FILE" ]; then
    cp "$EXISTING_COMPOSE_FILE" "$ORIGINAL_COMPOSE_TMPFILE"
    # `|| true` below: a non-zero exit here must not kill setup. That is exactly
    # how a missing python module turned into "Setup failed" with no explanation.
    # Runs from a file rather than an inline heredoc: bash 3.2 (macOS) could not
    # parse `$( ... << 'PYEOF' ... )` once the python contained a quote-heavy
    # expression, failing the whole script with "unexpected EOF". bash 5 parsed
    # it fine, so it passed every check on Linux.
    #
    # `|| true` because a non-zero exit here must never end setup — that is
    # exactly how a missing python module became "Setup failed" with no reason.
    ORIGINAL_COMPOSE_IS_COMPLEX=$(python3 "$DEV_DIR/scripts/compose_complexity.py" "$ORIGINAL_COMPOSE_TMPFILE" 2>/dev/null) || true
    [ -n "$ORIGINAL_COMPOSE_IS_COMPLEX" ] || ORIGINAL_COMPOSE_IS_COMPLEX=1
fi

if [ -n "$EXISTING_COMPOSE_FILE" ]; then
    # Complex projects are always adapted automatically — no confirmation needed.
    # For simple non-Zeltro composes, handle_docker_compose_conflict prompts the user
    # or can be bypassed with --overwrite-docker-compose.
    if [ "$ORIGINAL_COMPOSE_IS_COMPLEX" = "1" ]; then
        OVERWRITE_DOCKER_COMPOSE=1
    fi
    handle_docker_compose_conflict "$EXISTING_COMPOSE_FILE" "setup"
    # At this point, either the operation was cancelled (error/exit)
    # or overwrite has been confirmed/forced. Preserve the upstream compose
    # as a sidecar reference so devs can recover the original after Zeltro
    # rewrites docker-compose.yaml. Only created on the first run — never
    # overwrite an existing upstream backup.
    if [ ! -f "docker-compose.upstream.yaml" ]; then
        cp "$EXISTING_COMPOSE_FILE" docker-compose.upstream.yaml
    fi
    # Capture the GUI's x-metadata (emoji, display name, description) before the
    # file that holds it is deleted. Without this, re-running setup silently
    # wipes a user's project tile customisation.
    PRESERVED_X_METADATA="$(capture_x_metadata "$EXISTING_COMPOSE_FILE")"
    if [ -n "$PRESERVED_X_METADATA" ]; then
        echo-cyan "Preserving project metadata (emoji, name, description) ..."
    fi

    # Remove any existing docker-compose files so the Zeltro-managed one is the only source.
    rm -f docker-compose.yml docker-compose.yaml
fi


# Use absolute path to docker-stack directory
ZELTRO_DIR="$DEV_DIR"
if [ "$ORIGINAL_COMPOSE_IS_COMPLEX" = "1" ] && [ -f "$ORIGINAL_COMPOSE_TMPFILE" ]; then
    # Complex project: adapt the original docker-compose for Zeltro instead of using a cbc template.
    # Removes bundled DB/cache services, wires remaining services to zeltro-cli_vpc, assigns static IP.
    echo-cyan "Complex docker-compose detected — adapting for Zeltro environment..."
    # The python below writes the project's networks key; it reads the name
    # from the environment so an upgraded machine keeps its existing network.
    export ZELTRO_NETWORK_NAME="$(zeltro_network_name)"
    ADAPT_SUMMARY=$(python3 - "$IP_ADDRESS" "$PROJECT_NAME" "$D_CLASS" "$ORIGINAL_COMPOSE_TMPFILE" docker-compose.yaml "$CUSTOM_IMAGE" 2>/dev/null << 'PYEOF'
import sys, yaml, re, json

ip, project, d_class, src, dst = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
custom_image = sys.argv[6] if len(sys.argv) > 6 else ''

SHARED_BY_NAME = [
    (re.compile(r'^(postgres|postgresql|db|database|pg)$', re.I), 'zeltro-postgres'),
    (re.compile(r'^(mysql|mariadb)$', re.I),                      'zeltro-mariadb'),
    (re.compile(r'^(redis|cache|redis[-_]cache|valkey)$', re.I), 'zeltro-redis'),
    (re.compile(r'^(mongo|mongodb)$', re.I),                      'zeltro-mongo'),
    (re.compile(r'^(memcached|memcache)$', re.I),                 'zeltro-memcached'),
]
SHARED_BY_IMAGE = [
    (re.compile(r'^postgres(ql)?[:/]', re.I), 'zeltro-postgres'),
    (re.compile(r'^mysql[:/]', re.I),          'zeltro-mariadb'),
    (re.compile(r'^mariadb[:/]', re.I),        'zeltro-mariadb'),
    (re.compile(r'^redis[:/]', re.I),          'zeltro-redis'),
    (re.compile(r'^valkey[:/]', re.I),         'zeltro-redis'),
    (re.compile(r'^mongo(db)?[:/]', re.I),     'zeltro-mongo'),
]

doc = yaml.safe_load(open(src).read()) or {}
services = doc.get('services') or {}

replaced = {}
for name in list(services.keys()):
    svc = services[name] or {}
    image = str(svc.get('image', ''))
    matched = None
    for pat, host in SHARED_BY_NAME:
        if pat.match(name):
            matched = host; break
    if not matched:
        for pat, host in SHARED_BY_IMAGE:
            if pat.match(image):
                matched = host; break
    if matched:
        replaced[name] = matched
        del services[name]

WEB_NAMES = re.compile(r'^(nginx|web|app|api|server|frontend|backend|http)', re.I)
web_name = None
for name, svc in services.items():
    if (svc or {}).get('ports'):
        web_name = name; break
if not web_name:
    for name in services:
        if WEB_NAMES.match(name):
            web_name = name; break
if not web_name and services:
    web_name = next(iter(services))

for name, svc in services.items():
    svc = svc or {}
    env = svc.get('environment')
    if isinstance(env, dict):
        for k, v in list(env.items()):
            if isinstance(v, str) and v in replaced:
                env[k] = replaced[v]
    elif isinstance(env, list):
        new_env = []
        for item in env:
            if isinstance(item, str) and '=' in item:
                k, _, v = item.partition('=')
                if v in replaced:
                    v = replaced[v]
                item = f'{k}={v}'
            new_env.append(item)
        svc['environment'] = new_env
    dep = svc.get('depends_on')
    if isinstance(dep, list):
        new_dep = [d for d in dep if d not in replaced]
        if new_dep:
            svc['depends_on'] = new_dep
        else:
            svc.pop('depends_on', None)
    elif isinstance(dep, dict):
        for dead in list(replaced.keys()):
            dep.pop(dead, None)
        if not dep:
            svc.pop('depends_on', None)

for name, svc in services.items():
    svc = svc or {}
    if name == web_name:
        svc['container_name'] = project
        svc['networks'] = {'default': {'ipv4_address': ip}}
        # User-supplied --image overrides the upstream web service image.
        if custom_image:
            svc['image'] = custom_image
    else:
        svc['networks'] = ['default']

top_vols = doc.get('volumes') or {}
if top_vols:
    used = set()
    for svc in services.values():
        for v in (svc or {}).get('volumes', []):
            if isinstance(v, str) and ':' in v:
                src_v = v.split(':')[0]
                if not src_v.startswith('/') and not src_v.startswith('.'):
                    used.add(src_v)
    pruned = {k: v for k, v in top_vols.items() if k in used}
    if pruned:
        doc['volumes'] = pruned
    else:
        doc.pop('volumes', None)

doc['networks'] = {'default': {'external': True, 'name': os.environ.get('ZELTRO_NETWORK_NAME', 'zeltro-cli_vpc')}}

with open(dst, 'w') as f:
    yaml.dump(doc, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
print(json.dumps({'web_service': web_name, 'removed': list(replaced.keys()), 'zeltro_hosts': replaced}))
PYEOF
)
    if [ -f "docker-compose.yaml" ]; then
        _compose_file_created=1
        if [ -n "$ADAPT_SUMMARY" ]; then
            WEB_SVC=$(echo "$ADAPT_SUMMARY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('web_service','unknown'))" 2>/dev/null || echo "unknown")
            REMOVED=$(echo "$ADAPT_SUMMARY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.get('removed',[])))" 2>/dev/null || echo "")
            echo-green "  Web-facing service: $WEB_SVC (IP: $IP_ADDRESS)"
            [ -n "$REMOVED" ] && echo-cyan "  Replaced with Zeltro shared services: $REMOVED"
            [ -n "$CUSTOM_IMAGE" ] && echo-cyan "  Using custom image: $CUSTOM_IMAGE"
        fi
        rm -f "$ORIGINAL_COMPOSE_TMPFILE"
        # Note: image type only affects this compose adaptation. Framework steps
        # (composer install, .env wiring, storage symlink, migrations) are driven
        # by framework DETECTION in the startup branch below and run for adapted
        # projects too. Use --no-startup to defer and review the compose first.
    else
        echo-yellow "Warning: docker-compose adaptation failed — falling back to Zeltro template"
        rm -f "$ORIGINAL_COMPOSE_TMPFILE"
        ORIGINAL_COMPOSE_IS_COMPLEX=0
    fi
fi

if [ "$ORIGINAL_COMPOSE_IS_COMPLEX" != "1" ]; then
    rm -f "$ORIGINAL_COMPOSE_TMPFILE" 2>/dev/null || true
    if [ "$FRAMEWORK_IS_PYTHON" = "1" ]; then
        cp -f "$ZELTRO_DIR/docker-stack/docker-compose.python3-project.yaml" docker-compose.yaml
        sed -i "s|name: zeltro-cli_vpc|name: $(zeltro_network_name)|" docker-compose.yaml
    elif [ "$FRAMEWORK_IS_NODE" = "1" ]; then
        cp -f "$ZELTRO_DIR/docker-stack/docker-compose.node-project.yaml" docker-compose.yaml
        sed -i "s|name: zeltro-cli_vpc|name: $(zeltro_network_name)|" docker-compose.yaml
    else
        cp -f "$ZELTRO_DIR/docker-stack/docker-compose.php8.yaml" docker-compose.yaml
        sed -i "s|name: zeltro-cli_vpc|name: $(zeltro_network_name)|" docker-compose.yaml
    fi
    _compose_file_created=1

    zeltro-sed "s/IPV4_ADDRESS/$IP_ADDRESS/g" docker-compose.yaml
    zeltro-sed "s/CONTAINER_NAME/$PROJECT_NAME/g" docker-compose.yaml
    zeltro-sed "s/PROJECT_PORT/$D_CLASS/g" docker-compose.yaml

    if [ -d "public" ] || [ "$FRAMEWORK_IS_PYTHON" = "1" ] || [ "$FRAMEWORK_IS_NODE" = "1" ]; then
        zeltro-sed "s/PUBLIC//g" docker-compose.yaml
    else
        zeltro-sed "s/PUBLIC/\/public/g" docker-compose.yaml
    fi

    if [ "$FRAMEWORK_IS_PYTHON" = "1" ]; then
        zeltro-sed "s|PYTHON_START_COMMAND|$(framework_python_start_command)|g" docker-compose.yaml
    elif [ "$FRAMEWORK_IS_NODE" = "1" ]; then
        zeltro-sed "s|NODE_START_COMMAND|$(framework_node_start_command)|g" docker-compose.yaml
    fi

    # Override the framework's default cbc base image when the user supplied --image.
    # The template has a single server-service image line; replace it in place.
    if [ -n "$CUSTOM_IMAGE" ]; then
        zeltro-sed "s|^\([[:space:]]*image:\)[[:space:]].*|\1 $CUSTOM_IMAGE|" docker-compose.yaml
        echo-cyan "Using custom image: $CUSTOM_IMAGE"
    fi
fi

# Put the GUI's x-metadata back into the regenerated compose. Runs for BOTH the
# template path and the adapted-upstream path, so metadata survives either kind
# of regeneration.
if [ -n "${PRESERVED_X_METADATA:-}" ] && [ -f "docker-compose.yaml" ]; then
    if restore_x_metadata "docker-compose.yaml" "$PROJECT_NAME" "$PRESERVED_X_METADATA"; then
        echo-green "Project metadata preserved."
    else
        echo-yellow "Could not reattach project metadata — the GUI may show default emoji/name."
        echo-white  "Previous values:"
        printf '%s\n' "$PRESERVED_X_METADATA" | sed 's/^/    /'
    fi
fi

# When we replaced an upstream compose, the new docker-compose.yaml is
# Zeltro-managed and shouldn't be committed back to the project's repo —
# it would break non-Zeltro teammates. Add it to .gitignore (idempotent).
# Note: if the file was already git-tracked upstream, the user will still
# see modifications in `git status` and needs `git rm --cached` to fully
# untrack it; we intentionally don't run that automatically.
if [ -n "$EXISTING_COMPOSE_FILE" ]; then
    if ! grep -qxF "docker-compose.yaml" .gitignore 2>/dev/null; then
        {
            [ -f .gitignore ] && echo ""
            echo "# Generated by Zeltro — see docker-compose.upstream.yaml for the original"
            echo "docker-compose.yaml"
        } >> .gitignore
    fi
fi

# Start the project container before composer installation
cd "$PROJECT_DIR"

echo-cyan "Current directory: $(pwd)"

if [ "$NO_STARTUP" = "1" ]; then
    echo-yellow "Container startup deferred — run 'zeltro up $PROJECT_NAME' after verifying docker-compose.yaml"
else
    echo-cyan "Starting project container for composer installation..."

    # Start the project and capture output if in JSON mode
    debug "About to start project container via startup.sh"
    debug "Current directory before startup: $(pwd)"
    # startup.sh expects to be run from the projects directory
    cd "$PROJECTS_DIR_PATH"
    debug "Changed to projects directory: $(pwd)"

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        debug "Calling startup.sh in JSON mode"
        STARTUP_OUTPUT=$(source "$DEV_DIR/scripts/startup.sh" "$PROJECT_NAME" 2>&1)
        STARTUP_EXIT_CODE=$?
        debug "startup.sh completed with exit code: $STARTUP_EXIT_CODE"
    else
        debug "Calling startup.sh in interactive mode"
        source "$DEV_DIR/scripts/startup.sh" "$PROJECT_NAME"
        STARTUP_EXIT_CODE=$?
        debug "startup.sh completed with exit code: $STARTUP_EXIT_CODE"
    fi

    if [ $STARTUP_EXIT_CODE -ne 0 ]; then
        debug "startup.sh failed, calling error function"
        error "Failed to start project container"
    fi
    debug "Project container started successfully"
    _container_started=1

    # Return to project directory after startup (startup.sh may have changed working directory)
    debug "Returning to project directory: $PROJECT_DIR"
    cd "$PROJECT_DIR"
    debug "Current directory after returning: $(pwd)"
fi

if [ "$NO_STARTUP" != "1" ]; then
    # Patch Django settings.py for cloned projects that haven't been patched yet (idempotent)
    SETTINGS_FILE="${PROJECT_NAME_SNAKE}/settings.py"
    if [ -f "manage.py" ] && [ -f "$SETTINGS_FILE" ] && ! grep -q "load_dotenv" "$SETTINGS_FILE"; then
        echo-cyan "Patching Django settings.py ..."; echo-white

        printf 'from dotenv import load_dotenv\nfrom pathlib import Path\nimport os\nimport pymysql\npymysql.install_as_MySQLdb()\nload_dotenv(Path(__file__).resolve().parent.parent / ".env")\n\n' | cat - "$SETTINGS_FILE" > /tmp/zeltro_settings_tmp.py && mv /tmp/zeltro_settings_tmp.py "$SETTINGS_FILE"

        zeltro-sed "s|^ALLOWED_HOSTS = \[.*\]|ALLOWED_HOSTS = [os.getenv('APP_URL', '').replace('http://', '').replace('https://', ''), '']|" "$SETTINGS_FILE"

        python3 - "$SETTINGS_FILE" << 'PYEOF'
import re, sys
path = sys.argv[1]
content = open(path).read()
new_db = """DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.' + os.getenv('DB_CONNECTION', 'mysql'),
        'NAME': os.getenv('DB_DATABASE', ''),
        'USER': os.getenv('DB_USERNAME', 'root'),
        'PASSWORD': os.getenv('DB_PASSWORD', ''),
        'HOST': os.getenv('DB_HOST', ''),
        'PORT': os.getenv('DB_PORT', '3306'),
    }
}"""
content = re.sub(r'DATABASES\s*=\s*\{[^}]*\{[^}]*\}[^}]*\}', new_db, content, flags=re.DOTALL)
open(path, 'w').write(content)
PYEOF
        echo-green "Django settings.py patched!"; echo-white
    fi

    # Install Composer libraries
    debug "Checking for composer.json file"
    if [ -f "composer.json" ]; then
        debug "Found composer.json, installing dependencies"
        echo-cyan "Installing vendor libs with composer ..."; echo-white

        debug "About to call json-composer install"
        json-composer install
        COMPOSER_EXIT_CODE=$?
        debug "json-composer install completed with exit code: $COMPOSER_EXIT_CODE"

        debug "Composer installation completed"
        echo-green "Vendor libs installed!"; echo-white
    else
        debug "No composer.json found"
    fi

    # Install npm dependencies for Node projects
    if [ "$FRAMEWORK_IS_NODE" = "1" ] && [ -f "package.json" ]; then
        echo-cyan "Installing Node dependencies with npm ..."; echo-white
        # npm can die with ENOTEMPTY here: if the install is interrupted, its own
        # rollback tries to rmdir directories that are not empty on overlayfs and
        # cannot recover the tree in place. Retrying on top of the wreckage fails
        # the same way, so the retry clears node_modules first.
        #
        # --no-audit/--no-fund cut network round-trips, and --no-progress keeps npm
        # from rendering a progress bar into a pipe -- this reproduces when zeltro
        # is spawned with piped stdio (a GUI) but not from a terminal.
        _npm_install_in_container() {
            local quiet="$1"
            local cmd="cd /usr/share/nginx/html && npm install --no-audit --no-fund --no-progress"
            if [ "$quiet" = "1" ]; then
                docker exec "$PROJECT_NAME" bash -c "$cmd" > /dev/null 2>&1
            else
                docker exec "$PROJECT_NAME" bash -c "$cmd"
            fi
        }
        _npm_quiet=0
        [[ "$JSON_OUTPUT" == "1" ]] && _npm_quiet=1
        if ! _npm_install_in_container "$_npm_quiet"; then
            echo-yellow "npm install failed — clearing node_modules and retrying once ..."; echo-white
            docker exec "$PROJECT_NAME" bash -c "rm -rf /usr/share/nginx/html/node_modules" 2>/dev/null || true
            _npm_install_in_container "$_npm_quiet"
        fi
        echo-green "Node dependencies installed!"; echo-white
        # Fix ownership so the host user can run zeltro npm install afterwards without EACCES
        docker exec "$PROJECT_NAME" bash -c "chown -R $(id -u):$(id -g) /usr/share/nginx/html/node_modules /usr/share/nginx/html/package-lock.json 2>/dev/null || true"
        # Discard dev-server build caches before restarting.
        #
        # supervisor starts node-app as soon as the container is up, long before
        # npm install has finished writing node_modules. Those early attempts
        # fail harmlessly ("nuxt: not found") until one gets far enough to begin
        # dependency pre-bundling and is then cut off mid-scan. Nuxt writes a
        # half-built cache at that point and never recovers: every request
        # returns 500 with a missing vite socket, on a project whose install
        # exited 0.
        #
        # These are all regenerated on next boot, so clearing them costs a few
        # seconds of first load and removes the whole failure mode.
        docker exec "$PROJECT_NAME" bash -c \
            "cd /usr/share/nginx/html && rm -rf .nuxt .next .svelte-kit .astro node_modules/.vite node_modules/.cache" \
            > /dev/null 2>&1 || true
        # Restart the whole container, not just the supervisor program, so the
        # dev server picks up the freshly installed packages.
        #
        # `supervisorctl restart node-app` is not enough. This image's supervisor
        # config has no stopasgroup/killasgroup, so a dev server that spawns
        # children (Nuxt forks Vite; Vite forks esbuild) leaves them running when
        # the program is stopped. The orphan keeps holding port 3000, every
        # replacement instance fails to bind, and the project serves nothing --
        # after an install that exited 0. Single-process servers like Express and
        # Hono never showed this, which is why it stayed hidden.
        #
        # Restarting the container kills the whole PID namespace's strays and is
        # what `zeltro up` does later anyway, so it is the state we want to land
        # in regardless.
        docker restart "$PROJECT_NAME" > /dev/null 2>&1 || true
        # Wait for the container to accept exec again before anything downstream
        # tries to use it.
        for _i in $(seq 1 30); do
            docker exec "$PROJECT_NAME" true > /dev/null 2>&1 && break
            sleep 1
        done
    fi

    # Install Python dependencies for Python projects
    if [ "$FRAMEWORK_IS_PYTHON" = "1" ] && [ -f "requirements.txt" ]; then
        echo-cyan "Installing Python dependencies ..."; echo-white
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            docker exec "$PROJECT_NAME" bash -c "cd /usr/share/nginx/html && pip3 install --break-system-packages -r requirements.txt" > /dev/null 2>&1
        else
            docker exec "$PROJECT_NAME" bash -c "cd /usr/share/nginx/html && pip3 install --break-system-packages -r requirements.txt"
        fi
        echo-green "Python dependencies installed!"; echo-white
    fi

    # Install and build front-end assets when Vite/Laravel is detected (host-side Node)
    if [ -f "package.json" ]; then
        if grep -qi '"vite"' package.json; then
            debug "Detected Vite configuration in package.json; installing Node dependencies and building assets on host"
            if [[ "$JSON_OUTPUT" != "1" ]]; then
                echo-cyan "Installing Node dependencies on host (npm install) ..."; echo-white
            fi
            if [[ "$JSON_OUTPUT" == "1" ]]; then
                if ! npm install >/dev/null 2>&1; then
                    echo-yellow "Warning: npm install failed on host. Vite assets may not be built."; echo-white
                else
                    if ! npm run build >/dev/null 2>&1; then
                        echo-yellow "Warning: npm run build failed on host. Vite manifest may be missing."; echo-white
                    fi
                fi
            else
                if ! npm install; then
                    echo-yellow "Warning: npm install failed on host. Vite assets may not be built."; echo-white
                else
                    echo-green "Node dependencies installed."; echo-white
                    echo-cyan "Building front-end assets on host (npm run build) ..."; echo-white
                    if ! npm run build; then
                        echo-yellow "Warning: npm run build failed on host. Vite manifest may be missing."; echo-white
                    else
                        echo-green "Front-end assets built successfully."; echo-white
                    fi
                fi
            fi
        else
            debug "package.json found but no Vite references detected; skipping npm install/build"
        fi
    fi

    # Install and setup .env / config file.
    unalias cp 2>/dev/null || true
    if [ -n "$EXISTING_COMPOSE_FILE" ] && [ -f ".env" ]; then
        # Adopting an existing app that ships its own .env: never regenerate it
        # from a template (would lose real config + APP_KEY). Detect its DB engine
        # so DB creation + migrations match, then rewrite only the connection
        # settings to the shared services when --overwrite-env is set.
        _conn=$(grep -E "^#*[[:space:]]*DB_CONNECTION=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d "\"' ")
        case "$_conn" in
            pgsql|postgres|postgresql) DATABASE_ENGINE="postgres" ;;
            mongodb|mongo)             DATABASE_ENGINE="mongo" ;;
            mysql|mariadb)             DATABASE_ENGINE="mysql" ;;
        esac
        if [ "$OVERWRITE_ENV" = "1" ]; then
            rewrite_env_for_shared_services "$DB_NAME" "$DATABASE_ENGINE"
        else
            echo-yellow "Keeping existing .env (pass --overwrite-env to rewrite connection settings for Zeltro)."
        fi
    else
        # Greenfield / template-based project: generate the framework's .env.
        framework_setup_env
    fi

    echo-return; echo-return

    # Make storage writable for all
    if [ -d "storage" ]; then

        echo-cyan 'Setting folder permissions ...'; echo-white

        find storage -type d -exec chmod 777 {} +

        # setfacl comes from the `acl` package, which is NOT present on a stock
        # Ubuntu or Fedora install. Under `set -e` a missing binary aborted the
        # entire setup — a project that was otherwise complete got rolled back.
        # The chmod above already grants the access needed; the default ACL only
        # makes it stick for files created later, so its absence is a downgrade,
        # not a failure.
        if command -v setfacl >/dev/null 2>&1; then
            find storage -type d -exec setfacl -m "default:group::rw" {} + || true
        else
            echo-yellow "setfacl not found (install the 'acl' package) — skipping default ACLs."
        fi

        echo-green 'Storage folder permissions set!'; echo-white

        # Create storage symlink for Laravel unless disabled
        if [ "$SKIP_STORAGE_SYMLINK" != "true" ] && [ -f "artisan" ]; then
            if [ -d "public" ] && [ -d "storage/app/public" ]; then
                if [ -L "public/storage" ]; then
                    :
                elif [ -e "public/storage" ]; then
                    echo-yellow "public/storage exists and is not a symlink. Skipping storage symlink creation."
                else
                    ln -s ../storage/app/public public/storage
                    if [[ "$JSON_OUTPUT" != "1" ]]; then
                        echo-green "Symlink created: public/storage -> ../storage/app/public"
                    fi
                fi
            fi
        fi

    fi

    # Create new database (idempotent — if it already exists, just continue).
    # The engine must be running before we can create a database in it.
    # When the app's own .env is kept, the database that matters is the one it
    # names -- that is what migrations connect to. Creating the project-named
    # database instead produced "Database ready!" followed by
    # "Unknown database 'laravel_flat_file_website'".
    if [ "$KEEP_EXISTING_ENV" = "1" ]; then
        _env_conn=$(grep -E '^[[:space:]]*DB_CONNECTION=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\"' \r")
        _env_db=$(grep -E '^[[:space:]]*DB_DATABASE=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\"' \r")
        case "$_env_conn" in
            pgsql|postgres|postgresql) DATABASE_ENGINE="postgres" ;;
            mongodb|mongo)             DATABASE_ENGINE="mongo" ;;
            mysql|mariadb)             DATABASE_ENGINE="mysql" ;;
            sqlite)                    DATABASE_ENGINE="sqlite" ;;
        esac
        if [ "$DATABASE_ENGINE" != "sqlite" ] && [ -n "$_env_db" ] && [ "$_env_db" != "$DB_NAME" ]; then
            if [[ "$_env_db" =~ ^[A-Za-z0-9_]+$ ]]; then
                if [ -n "$DB_NAME_OVERRIDE" ]; then
                    echo-yellow "--db-name '$DB_NAME' not applied: the kept .env uses '$_env_db'. Pass --overwrite-env to switch it."
                else
                    echo-cyan "Using database '$_env_db' from the existing .env (project name would give '$DB_NAME')."
                fi
                DB_NAME="$_env_db"
                export DB_NAME
            else
                echo-yellow "The existing .env names database '$_env_db', which is not a plain name Zeltro will create."
                echo-yellow "Skipping migrations. Create it yourself, or pass --overwrite-env to use '$DB_NAME'."
                RUN_MIGRATIONS=0
            fi
        fi
    fi

    ensure_services_for_project "$PROJECT_NAME" || true
    ensure_database "$DB_NAME" "$DATABASE_ENGINE"

    # Migrations run by default (driven by framework detection). For adopted
    # projects (MIGRATE_SAFE=1) frameworks use non-destructive migrate; greenfield
    # uses the full reset+seed. --no-migration skips them entirely.
    if [ "$RUN_MIGRATIONS" = "1" ]; then
        framework_run_migrations
    else
        echo-yellow "Skipping migrations (--no-migration)."
    fi

    echo-return; echo-return

    # Setup gitignore
    framework_setup_gitignore
fi

# Setup completed
if [[ "$JSON_OUTPUT" == "1" ]]; then
    # Build JSON response with optional fields
    JSON_RESPONSE="{\"action\": \"setup_project\", \"project_name\": \"$PROJECT_NAME\", \"database\": \"$DATABASE_ENGINE\", \"status\": \"success\", \"startup_deferred\": $([ "$NO_STARTUP" = "1" ] && echo "true" || echo "false")"

    # Add shutdown result if captured
    if [ -n "$SHUTDOWN_OUTPUT" ]; then
        JSON_RESPONSE="$JSON_RESPONSE, \"shutdown_result\": $SHUTDOWN_OUTPUT"
    fi

    # Add startup result if captured
    if [ -n "$STARTUP_OUTPUT" ]; then
        JSON_RESPONSE="$JSON_RESPONSE, \"startup_result\": $STARTUP_OUTPUT"
    fi

    # Tell the caller which shared services THIS run had to enable, and which
    # admin UIs could manage them. The GUI uses it to offer "you just got a
    # Postgres — want something to browse it with?" at the one moment the user
    # is thinking about it.
    JSON_RESPONSE="$JSON_RESPONSE$(zeltro_services_json_fragment)"

    JSON_RESPONSE="$JSON_RESPONSE}"
    echo "$JSON_RESPONSE"
else
    echo-return; echo-return
    if [ "$NO_STARTUP" = "1" ]; then
        echo-green "Docker-compose adapted for project: $PROJECT_NAME"
        echo-white "IP address: $IP_ADDRESS"
        echo-yellow "Container not started. Review docker-compose.yaml then run: zeltro up $PROJECT_NAME"
    else
        echo-green "Setup completed for project: $PROJECT_NAME"
        echo-white "Database: $DATABASE_ENGINE"
        echo-return

        # Build status options
        STATUS_OPTIONS=""
        if [[ "$NO_COLOR" == "1" ]]; then
            STATUS_OPTIONS="$STATUS_OPTIONS --no-colors"
        fi

        # Give the just-started app time to bind before the HTTP check calls it
        # failed (see curl_status in status.sh).
        export HTTP_WAIT_SECS="${HTTP_WAIT_SECS:-45}"

        # Show status to confirm successful startup
        source "$DEV_DIR/scripts/status.sh" $PROJECT_NAME $STATUS_OPTIONS
    fi
fi

# Return to original directory
cd "$ORIG_DIR"
