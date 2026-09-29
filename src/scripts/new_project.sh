#!/bin/bash

set -e


ORIG_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"

cd ..

DEV_DIR=$(pwd)

source scripts/pre_check.sh

# Use projects directory from pre_check
PROJECTS_DIR="$PROJECTS_DIR_PATH"

NEW_PROJECT_FORCE_FORK="${NEW_PROJECT_FORCE_FORK:-0}"
FORK_USED=0


# Function to get latest Laravel version from GitHub API.
# Returns non-zero and sets GITHUB_API_ERROR if the version cannot be determined.
#
# This used to be a bare `curl -s | grep | sed` whose failure was silent: a
# rate-limited API returns a 14-byte JSON error, the sed matches nothing, and the
# caller happily built a download URL with an EMPTY version in it. curl then
# fetched GitHub's 404 page and piped it to tar, so the user's entire diagnosis
# was "gzip: stdin: not in gzip format" — which says nothing about rate limits,
# the network, or anything they could act on. Shawn hit exactly this.
get_latest_laravel_version() {
    local json version

    # git ls-remote first: it speaks the git protocol, so it is not subject to
    # the REST API's rate limit AT ALL — this removes the dependency rather than
    # just raising the ceiling — and it is faster than the API call. Uses SSH
    # when the user's key works, since that is authenticated and needs no token.
    local repo="https://github.com/laravel/laravel"
    if github_ssh_works; then
        repo="git@github.com:laravel/laravel.git"
    fi
    if version="$(github_latest_tag "$repo")"; then
        printf '%s' "$version"
        return 0
    fi

    # Fall back to the API only if git could not reach the remote at all.
    json="$(github_api_get "https://api.github.com/repos/laravel/laravel/tags")" || return 1

    version="$(printf '%s' "$json" | grep '"name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')"
    if [ -z "$version" ]; then
        GITHUB_API_ERROR="GitHub returned a response with no recognisable Laravel version tag."
        return 1
    fi
    printf '%s' "$version"
}

# Validate that a Laravel version exists.
#   0 = exists   1 = does not exist   2 = COULD NOT CHECK (API unavailable)
#
# The third state matters: without it, a rate-limited API makes a perfectly valid
# version look invalid, and the user is told their input is wrong when it is not.
validate_laravel_version() {
    local version="$1"
    if [ "$version" = "latest" ]; then
        return 0
    fi

    local version_with_v="$version"
    if [[ ! "$version" =~ ^v ]]; then
        version_with_v="v${version}"
    fi

    # Same reasoning as get_latest_laravel_version: ls-remote is rate-limit-free,
    # so the common case never consumes API budget.
    local repo="https://github.com/laravel/laravel"
    github_ssh_works && repo="git@github.com:laravel/laravel.git"

    local tags
    if tags="$(git ls-remote --tags --refs "$repo" 2>/dev/null)" && [ -n "$tags" ]; then
        printf '%s' "$tags" | grep -q "refs/tags/${version_with_v}\$"
        return $?
    fi

    local json
    json="$(github_api_get "https://api.github.com/repos/laravel/laravel/tags?per_page=100")" || return 2

    printf '%s' "$json" | grep -q "\"name\": \"${version_with_v}\""
}

# Function to validate WordPress version exists
validate_wordpress_version() {
    local version="$1"
    if [ "$version" = "latest" ]; then
        return 0
    fi
    # Check if the WordPress version exists
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://wordpress.org/wordpress-${version}.tar.gz")
    [ "$status_code" = "200" ]
}

# Function to display usage
usage() {
    echo-white "Usage: ${ZELTRO_CMD:-$0} <framework> <name> [options]"
    echo-white "Creates a new greenfield project from a framework skeleton"
    echo-white ""
    echo-white "Arguments:"
    echo-white "  framework       laravel, kavera, octobercms, drupal, wordpress, php, fastapi, flask,"
    echo-white "                  django, python, express, nestjs, fastify, node, nextjs, nuxt,"
    echo-white "                  sveltekit, astro, hono, react, vue"
    echo-white "  name            Name of the project to create (directory and hostname)"
    echo-white ""
    echo-white "Options:"
    echo-white "  --version VERSION       Framework version (laravel, wordpress). Ignored by other frameworks."
    echo-white "  --database TYPE         Database type: mysql, postgres, mongo, sqlite (default: mysql)"
    echo-white "  --image REF             Override the project's Docker image (default: framework cbc base image)"
    echo-white "  --db-name NAME          Database name (default: project name with dashes as underscores)"
    echo-white "  --no-migration          Skip database migrations (they run by default)"
    echo-white "  --no-storage-symlink    Skip creating public/storage symlink (Laravel only)"
    echo-white "  --github                Create GitHub repository in user account"
    echo-white "  --github-org ORG        Create GitHub repository in organization"
    echo-white "  --public                Make the new GitHub repository public (default: private)"
    echo-white "  --private               Make the new GitHub repository private"
    echo-white "  --one-off               Skip the interactive AI session at the end (for automation)"
    echo-white "  --json-output           Output JSON responses (for programmatic use)"
    echo-white "  --no-colors             Disable colored output"
    echo-white "  --debug                 Enable debug logging to /tmp/zeltro-cli-debug.log"
    echo-white ""
    echo-white "Examples:"
    echo-white "  ${ZELTRO_CMD:-$0} laravel my-app --database postgres --github"
    echo-white "  ${ZELTRO_CMD:-$0} wordpress my-blog --github-org myorg"
    echo-white "  ${ZELTRO_CMD:-$0} flask my-api --database sqlite"
}

# Resolve Laravel repository URL (allows HTTPS or SSH via /etc/zeltro-cli/.env)
if [ -z "$LARAVEL_REPOSITORY_URL" ] && [ -f "/etc/zeltro-cli/.env" ]; then
    LARAVEL_REPOSITORY_URL=$(grep "^LARAVEL_REPOSITORY_URL=" "/etc/zeltro-cli/.env" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'")
fi
# Initialize variables
PROJECT_NAME=""
ORGANIZATION=""
VERSION="latest"
FRAMEWORK=""
DATABASE="auto"
CREATE_GITHUB=""
GITHUB_VISIBILITY=""
SKIP_STORAGE_SYMLINK=0
SKIP_INTERACTIVE=0
DB_NAME_OVERRIDE=""
CUSTOM_IMAGE=""
# Greenfield projects: Zeltro owns the .env, so always (re)write it. Some
# scaffolders (e.g. Laravel's composer create-project) drop a stock .env that
# must be replaced with Zeltro's configured one.
OVERWRITE_ENV=1
RUN_MIGRATIONS=1

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME_OVERRIDE="$2"
            shift 2
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
        --no-storage-symlink)
            SKIP_STORAGE_SYMLINK=1
            shift
            ;;
        --one-off)
            SKIP_INTERACTIVE=1
            shift
            ;;
        --no-github)
            CREATE_GITHUB="no"
            shift
            ;;
        --github)
            CREATE_GITHUB="yes"
            shift
            ;;
        --github-org)
            CREATE_GITHUB="org"
            ORGANIZATION="$2"
            shift 2
            ;;
        --public)
            GITHUB_VISIBILITY="public"
            shift
            ;;
        --private)
            GITHUB_VISIBILITY="private"
            shift
            ;;
        --json-output)
            JSON_OUTPUT=1
            shift
            ;;
        --no-colors)
            NO_COLOR=1
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
            echo-red "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            # Positional order: <framework> <name>
            if [ -z "$FRAMEWORK" ]; then
                FRAMEWORK="$1"
            elif [ -z "$PROJECT_NAME" ]; then
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
debug "Script started: new_project.sh with args: $ORIGINAL_ARGS"

# --- Required arguments (no interactive prompts; 'configure' is the only wizard) ---
if [ -z "$FRAMEWORK" ]; then
    error "Error: framework is required. Usage: zeltro new <framework> <name> [--database <type>] [--version X]
Frameworks: laravel kavera octobercms drupal wordpress php fastapi flask django python express nestjs fastify node nextjs nuxt sveltekit astro hono react vue"
fi
case "$FRAMEWORK" in
    laravel|kavera|octobercms|drupal|wordpress|php|fastapi|flask|django|python|express|nestjs|fastify|node|nextjs|nuxt|sveltekit|astro|hono|react|vue) ;;
    *)
        # `new` scaffolds a framework you write; `install` deploys a prebuilt
        # app. Nobody should have to know which bucket a name lives in, so if
        # this name is actually an installer, point straight at the right
        # command instead of listing frameworks they didn't ask about.
        if [ -f "$DEV_DIR/installers/$FRAMEWORK.sh" ]; then
            _disp=$(grep -m1 '^INSTALL_DISPLAY=' "$DEV_DIR/installers/$FRAMEWORK.sh" 2>/dev/null | cut -d'"' -f2)
            echo-yellow "'$FRAMEWORK' is an app, not a framework."
            echo-white "${_disp:-$FRAMEWORK} ships as a ready-to-run install rather than something you scaffold."
            echo-return
            echo-cyan "Run this instead:"
            echo-white "  zeltro install $FRAMEWORK${PROJECT_NAME:+ $PROJECT_NAME}"
            echo-return
            error "Wrong command for '$FRAMEWORK' — use 'zeltro install'."
        fi
        error "Error: invalid framework '$FRAMEWORK'. Choose: laravel, kavera, octobercms, drupal, wordpress, php, fastapi, flask, django, python, express, nestjs, fastify, node, nextjs, nuxt, sveltekit, astro, hono, react, vue."
        ;;
esac
if [ -z "$PROJECT_NAME" ]; then
    error "Error: project name is required. Usage: zeltro new $FRAMEWORK <name>"
fi

# Resolve database: 'auto' (or empty) → sensible per-framework default.
if [ -z "$DATABASE" ] || [ "$DATABASE" = "auto" ]; then
    case "$FRAMEWORK" in
        django|fastapi|flask|python) DATABASE="postgres" ;;
        # Front-end-leaning frameworks default to SQLite so a new project does
        # not start a database server it never queries. Pass --database
        # explicitly to get one.
        nextjs|nuxt|sveltekit|astro|hono|react|vue) DATABASE="sqlite" ;;
        *)                     DATABASE="mysql" ;;
    esac
    echo-cyan "Auto-selected database for $FRAMEWORK: $DATABASE"
fi
# Constrain the engine to what this framework actually supports. Rules live in
# src/catalog/frameworks.json rather than as per-framework special cases here.
if [ -n "$DATABASE" ] && [ "$DATABASE" != "auto" ]; then
    DATABASE=$(resolve_framework_database "$FRAMEWORK" "$DATABASE")
fi

# Validation for JSON output mode
debug "Starting validation phase"
if [[ "$JSON_OUTPUT" == "1" ]]; then
    debug "JSON output mode enabled"
    # Required options validation
    if [ -z "$PROJECT_NAME" ]; then
        json_error "project name is required when using --json-output"
    fi
    
    # Set defaults for JSON mode
    if [ -z "$FRAMEWORK" ]; then
        FRAMEWORK="laravel"
    fi
    
    # Set version defaults based on framework
    if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then
        case "$FRAMEWORK" in
            "laravel"|"wordpress")
                VERSION="latest"
                ;;
            "php")
                VERSION="8"
                ;;
            *)
                VERSION="latest"
                ;;
        esac
    fi
    
    # Set default database
    if [ -z "$DATABASE" ]; then
        DATABASE="mysql"
    fi
    
    # Framework validation
    case "$FRAMEWORK" in
        "laravel"|"kavera"|"octobercms"|"drupal"|"wordpress"|"php"|"fastapi"|"flask"|"django"|"python"|"express"|"nestjs"|"fastify"|"node"|"nextjs"|"nuxt"|"sveltekit"|"astro"|"hono"|"react"|"vue")
            # Valid frameworks
            ;;
        *)
            json_error "invalid framework: $FRAMEWORK (must be laravel, kavera, octobercms, drupal, wordpress, php, fastapi, flask, django, python, express, nestjs, fastify, node, nextjs, nuxt, sveltekit, astro, hono, react, or vue)"
            ;;
    esac

    # Database validation
    case "$DATABASE" in
        "mysql"|"postgres"|"mongo"|"sqlite")
            # Valid databases
            ;;
        *)
            json_error "invalid database: $DATABASE (must be mysql, postgres, mongo, or sqlite)"
            ;;
    esac
    
    # GitHub organization validation
    if [ -z "$CREATE_GITHUB" ]; then
        CREATE_GITHUB="no"
    elif [ "$CREATE_GITHUB" = "org" ] && [ -z "$ORGANIZATION" ]; then
        json_error "organization is required when using --github-org"
    fi
    
    # GitHub CLI validation
    if [ "$CREATE_GITHUB" != "no" ]; then
        if ! command -v gh >/dev/null 2>&1; then
            json_error "GitHub CLI (gh) is not installed. Install it first or remove --github option"
        elif ! gh auth status >/dev/null 2>&1; then
            json_error "GitHub CLI (gh) is not authenticated. Run 'gh auth login' first or remove --github option"
        fi
    fi
else
    # Interactive mode - check GitHub CLI availability and warn if not available
    if [ "$CREATE_GITHUB" != "no" ]; then
        if ! command -v gh >/dev/null 2>&1; then
            echo-yellow "Warning: GitHub CLI (gh) is not installed."
            echo-yellow "GitHub repository creation has been disabled."
            echo-white "To enable GitHub integration, install gh CLI and run 'gh auth login'"
            CREATE_GITHUB="no"
        elif ! gh auth status >/dev/null 2>&1; then
            echo-yellow "Warning: GitHub CLI (gh) is not authenticated."
            echo-yellow "GitHub repository creation has been disabled."
            echo-white "To enable GitHub integration, run 'gh auth login'"
            CREATE_GITHUB="no"
        fi
    fi
fi

# Interactive mode if no project name provided
if [ -z "$PROJECT_NAME" ]; then
    echo-return
    echo-cyan "🚀 Create a New Zeltro Project"
    echo-return
    echo-white -n "Enter project name: "
    read PROJECT_NAME
    
    if [ -z "$PROJECT_NAME" ]; then
        error "Project name cannot be empty!"
    fi
    
    echo-white -n "Enter organization name (optional): "
    read ORGANIZATION
fi


# Convert to lowercase, replace spaces with dashes, and remove non-alphanumeric characters (macOS-compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
    PROJECT_NAME=$(echo "$PROJECT_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr ' ' '-' | LC_ALL=C tr -cd 'a-z0-9-_')
else
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_')
fi

# Check for duplicate project names
while [ -d "$PROJECTS_DIR/$PROJECT_NAME" ]; do
    if [[ "$JSON_OUTPUT" == "1" ]] || ! [ -t 0 ]; then
        json_error "project name '$PROJECT_NAME' already exists"
    else
        echo-red "Error: Project name '$PROJECT_NAME' already exists!"
        echo-yellow -n "Enter a different project name: "
        read NEW_PROJECT_NAME
        if [ -z "$NEW_PROJECT_NAME" ]; then
            error "Project name cannot be empty!"
        fi
        # Cleanse the new name (macOS-compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            PROJECT_NAME=$(echo "$NEW_PROJECT_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr ' ' '-' | LC_ALL=C tr -cd 'a-z0-9-_')
        else
            PROJECT_NAME=$(echo "$NEW_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_')
        fi
    fi
done


# Project type selection
# Framework selection
if [ -z "$FRAMEWORK" ]; then
    echo-return; echo-cyan "What type of project would you like to create?"
    echo-white "1) Laravel (PHP Framework)"
    echo-white "2) Kavera (PHP — Laravel-native website framework)"
    echo-white "3) October CMS (PHP — Laravel-based CMS)"
    echo-white "4) WordPress (CMS)"
    echo-white "5) PHP (Plain PHP project)"
    echo-white "6) FastAPI (Python Framework)"
    echo-white "7) Flask (Python Framework)"
    echo-white "8) Django (Python Framework)"
    echo-white "9) Python (Plain Python project)"
    echo-white "10) Express (Node.js Framework)"
    echo-white "11) NestJS (Node.js Framework)"
    echo-white "12) Fastify (Node.js Framework)"
    echo-white "13) Node.js (Plain Node.js)"
    echo-return; echo-yellow -n "Enter your choice (1-13): "
    read FRAMEWORK_CHOICE

    case $FRAMEWORK_CHOICE in
        1)
            FRAMEWORK="laravel"
            ;;
        2)
            FRAMEWORK="kavera"
            ;;
        3)
            FRAMEWORK="octobercms"
            ;;
        4)
            FRAMEWORK="wordpress"
            ;;
        5)
            FRAMEWORK="php"
            ;;
        6)
            FRAMEWORK="fastapi"
            ;;
        7)
            FRAMEWORK="flask"
            ;;
        8)
            FRAMEWORK="django"
            ;;
        9)
            FRAMEWORK="python"
            ;;
        10)
            FRAMEWORK="express"
            ;;
        11)
            FRAMEWORK="nestjs"
            ;;
        12)
            FRAMEWORK="fastify"
            ;;
        13)
            FRAMEWORK="node"
            ;;
    esac
fi

case $FRAMEWORK in
    laravel)
        echo-return; echo-cyan "Laravel project selected!"
        
        # Laravel version selection
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            # In JSON mode, validate the provided version
            if ! validate_laravel_version "$VERSION"; then
                json_error "invalid Laravel version: $VERSION"
            fi
            
            # Set the version for download in JSON mode
            if [ "$VERSION" = "latest" ]; then
                if ! LATEST_VERSION=$(get_latest_laravel_version); then
                    json_error "Could not determine the latest Laravel version. $GITHUB_API_ERROR"
                fi
                CUR_LARAVEL_BRANCH="v${LATEST_VERSION}"
            else
                # Ensure version has 'v' prefix for download URL
                if [[ ! "$VERSION" =~ ^v ]]; then
                    CUR_LARAVEL_BRANCH="v${VERSION}"
                else
                    CUR_LARAVEL_BRANCH="$VERSION"
                fi
            fi
        else
            # No prompt — validate the provided/default version and fail if invalid.
            # Exit 2 means the API could not be reached, NOT that the version is
            # bad; telling the user their input is wrong in that case is a lie.
            validate_laravel_version "$VERSION"; _ver_rc=$?
            if [ "$_ver_rc" = "2" ]; then
                error "Could not verify Laravel version '$VERSION'. $GITHUB_API_ERROR"
            elif [ "$_ver_rc" != "0" ]; then
                error "Error: invalid Laravel version '$VERSION'. Use 'latest' or a valid Laravel version tag."
            fi
        fi
        
        # Set the version for download
        if [ "$VERSION" = "latest" ]; then
            if ! LATEST_VERSION=$(get_latest_laravel_version); then
                echo-red "Could not determine the latest Laravel version."
                echo-white "  $GITHUB_API_ERROR"
                echo-white ""
                echo-white "Workaround: pin a version explicitly, which skips the lookup entirely:"
                echo-white "  zeltro new laravel $PROJECT_NAME --version 12.0.0"
                error "Aborting — refusing to download with an unknown version."
            fi
            CUR_LARAVEL_BRANCH="v${LATEST_VERSION}"
            echo-green "Using latest Laravel version: $LATEST_VERSION"
        else
            # Ensure version has 'v' prefix for download URL
            if [[ ! "$VERSION" =~ ^v ]]; then
                CUR_LARAVEL_BRANCH="v${VERSION}"
            else
                CUR_LARAVEL_BRANCH="$VERSION"
            fi
            echo-green "Laravel $VERSION selected!"
        fi
        ;;
    wordpress)
        echo-return; echo-cyan "WordPress project selected!"
        
        # WordPress version selection
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            # In JSON mode, validate the provided version
            if ! validate_wordpress_version "$VERSION"; then
                json_error "invalid WordPress version: $VERSION"
            fi
        else
            # No prompt — validate the provided/default version and fail if invalid.
            if ! validate_wordpress_version "$VERSION"; then
                error "Error: invalid WordPress version '$VERSION'. Use 'latest' or a valid WordPress version."
            fi
        fi
        
        WP_VERSION="$VERSION"
        if [ "$VERSION" = "latest" ]; then
            echo-green "Using latest WordPress version"
        else
            echo-green "WordPress $VERSION selected!"
        fi
        
        # WordPress only supports MySQL
        if [ "$DATABASE" != "mysql" ] && [ "$DATABASE" != "mariadb" ] && [ -n "$DATABASE" ]; then
            if [[ "$JSON_OUTPUT" == "1" ]]; then
                json_error "WordPress only supports MySQL/MariaDB database"
            else
                echo-yellow "Warning: WordPress only supports MySQL/MariaDB. Switching to MySQL."
                DATABASE="mysql"
            fi
        fi
        ;;
    kavera)
        # Kavera tracks its own repo rather than a versioned Laravel tag, so
        # there is no version to validate here — the scaffold hook downloads it.
        echo-return; echo-cyan "Kavera project selected!"
        echo-green "Kavera (Laravel-native website framework) will be downloaded."
        ;;
    octobercms)
        echo-return; echo-cyan "October CMS project selected!"
        echo-green "October CMS will be downloaded from source."
        ;;
    drupal)
        echo-return; echo-cyan "Drupal project selected!"
        echo-green "Drupal core will be installed by Composer, then drush site:install runs."
        echo-white "This is the slowest framework to create — expect several minutes."
        ;;
    php)
        echo-return; echo-cyan "PHP project selected!"
        
        # PHP projects don't need version validation
        echo-green "PHP project will be created with basic structure"
        ;;
    fastapi)
        echo-return; echo-cyan "FastAPI project selected!"
        echo-green "FastAPI project will be created with basic structure"
        ;;
    flask)
        echo-return; echo-cyan "Flask project selected!"
        echo-green "Flask project will be created with basic structure"
        ;;
    django)
        echo-return; echo-cyan "Django project selected!"
        echo-green "Django project will be scaffolded on the host."
        ;;
    python)
        echo-return; echo-cyan "Python project selected!"
        echo-green "Python project will be created with basic structure"
        ;;
    express)
        echo-return; echo-cyan "Express project selected!"
        echo-green "Express project will be created with basic structure"
        ;;
    nestjs)
        echo-return; echo-cyan "NestJS project selected!"
        echo-green "NestJS project will be created with basic structure"
        ;;
    fastify)
        echo-return; echo-cyan "Fastify project selected!"
        echo-green "Fastify project will be created with basic structure"
        ;;
    node)
        echo-return; echo-cyan "Node.js project selected!"
        echo-green "Node.js project will be created with basic structure"
        ;;
    nextjs|nuxt|sveltekit|astro|hono|react|vue)
        # These print their own banner from framework_scaffold; announcing them
        # here as well only produced the message twice.
        :
        ;;
    *)
        error "Unknown framework '$FRAMEWORK'. Exiting..."
        ;;
esac

# Load framework registry
source "$DEV_DIR/frameworks/${FRAMEWORK}.sh"

# Database selection
if [ -z "$DATABASE" ]; then
    if [[ "$JSON_OUTPUT" == "1" ]] || [ ! -t 0 ]; then
        DATABASE_TYPE="mysql"
    else
        echo-return; echo-cyan "Which database would you like to use?"
        echo-white "1) MySQL/MariaDB (Default)"
        echo-white "2) PostgreSQL"
        echo-white "3) MongoDB"
        echo-return; echo-yellow -n "Enter your choice (1-3): "
        read DB_CHOICE

        case $DB_CHOICE in
            1)
                DATABASE_TYPE="mysql"
                echo-green "MySQL/MariaDB selected!"
                ;;
            2)
                DATABASE_TYPE="postgres"
                echo-green "PostgreSQL selected!"
                ;;
            3)
                DATABASE_TYPE="mongo"
                echo-green "MongoDB selected!"
                ;;
            *)
                echo-yellow "Invalid choice. Defaulting to MySQL/MariaDB"
                DATABASE_TYPE="mysql"
                ;;
        esac
    fi
else
    case "$DATABASE" in
        mysql|mariadb)
            DATABASE_TYPE="mysql"
            echo-return; echo-cyan "MySQL/MariaDB selected!"
            ;;
        postgres|postgresql|postgressql)
            DATABASE_TYPE="postgres"
            echo-return; echo-cyan "PostgreSQL selected!"
            ;;
        mongo|mongodb)
            DATABASE_TYPE="mongo"
            echo-return; echo-cyan "MongoDB selected!"
            ;;
        *)
            echo-yellow "Unknown database '$DATABASE'. Defaulting to MySQL/MariaDB"
            DATABASE_TYPE="mysql"
            ;;
    esac
fi

echo-return; echo-return

# Set project name
cd "$PROJECTS_DIR"

if [ -d "$PROJECT_NAME" ]; then

	    error "Error: Project name already exists"

fi

mkdir "$PROJECT_NAME"
_PROJECT_DIR_CREATED=1

# Remove partially-built project directory on any subsequent failure.
#
# Split out from the trap handler because setup_project.sh is *sourced*, and a
# sourced `trap ... ERR` REPLACES this one in the same shell. When setup fails
# it therefore cleans up its own state and calls this directly -- otherwise the
# directory survives with no docker-compose.yaml and a retry starts dirty.
_remove_incomplete_project() {
    [ "$_PROJECT_DIR_CREATED" = "1" ] || return 0
    echo-yellow "Cleaning up incomplete project directory: $PROJECT_NAME"
    rm -rf "$PROJECTS_DIR/$PROJECT_NAME" 2>/dev/null || true
}

_new_project_cleanup() {
    local code=$?
    [ $code -eq 0 ] && return
    _remove_incomplete_project
}
trap _new_project_cleanup ERR

cd "$PROJECT_NAME"

framework_scaffold

# Zeltro filled this directory itself, so the first AI session can skip the
# agent's "do you trust this folder?" question (see the function for scope).
zeltro_trust_project_for_agents "$PWD"


# GitHub repository creation
# Skip repository creation when we already created a fork via GitHub CLI
if [[ "$FORK_USED" -ne 1 ]]; then
    # No prompt: default to NOT creating a repo unless --github/--github-org was passed.
    [ -z "$CREATE_GITHUB" ] && CREATE_GITHUB="no"

    # Create GitHub repository if requested
    if [ "$CREATE_GITHUB" != "no" ]; then
        create_github_repo "$PROJECT_NAME" "$CREATE_GITHUB" "$ORGANIZATION" "" "${GITHUB_VISIBILITY:-private}"
    fi
fi

cd ../..


# Setup project
# Build setup options
SETUP_OPTIONS=""
if [[ "$JSON_OUTPUT" == "1" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --json-output"
fi
if [[ "$NO_COLOR" == "1" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --no-colors"
fi
if [[ "$DEBUG" == "1" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --debug"
fi
if [[ -n "$DB_NAME_OVERRIDE" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --db-name $DB_NAME_OVERRIDE"
fi
if [[ -n "$CUSTOM_IMAGE" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --image $CUSTOM_IMAGE"
fi
if [[ "$OVERWRITE_ENV" == "1" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --overwrite-env"
fi
if [[ "$RUN_MIGRATIONS" == "0" ]]; then
    SETUP_OPTIONS="$SETUP_OPTIONS --no-migration"
fi

if [[ "$JSON_OUTPUT" == "1" ]]; then
    # In JSON mode, capture setup output and combine with new_project info
    if [[ "$SKIP_STORAGE_SYMLINK" == "1" ]]; then
        SETUP_OPTIONS="$SETUP_OPTIONS --no-storage-symlink"
    fi
    SETUP_OUTPUT=$(source "$DEV_DIR/scripts/setup_project.sh" "$PROJECT_NAME" "$DATABASE" $SETUP_OPTIONS 2>&1)
    SETUP_EXIT_CODE=$?
    
    if [ $SETUP_EXIT_CODE -ne 0 ]; then
        # Setup failed - output error and exit
        echo "{\"action\": \"new_project\", \"project_name\": \"$PROJECT_NAME\", \"framework\": \"$FRAMEWORK\", \"database\": \"$DATABASE\", \"status\": \"error\", \"error\": \"setup_failed\", \"details\": \"$SETUP_OUTPUT\"}"
        exit $SETUP_EXIT_CODE
    fi
    
    # Setup handles startup internally, so we just output the setup results
    echo "{\"action\": \"new_project\", \"project_name\": \"$PROJECT_NAME\", \"framework\": \"$FRAMEWORK\", \"database\": \"$DATABASE\", \"setup_result\": $SETUP_OUTPUT, \"status\": \"success\"}"
else
    # In normal mode, run setup with full output (setup handles startup internally)
    if [[ "$SKIP_STORAGE_SYMLINK" == "1" ]]; then
        SETUP_OPTIONS="$SETUP_OPTIONS --no-storage-symlink"
    fi
    source "$DEV_DIR/scripts/setup_project.sh" "$PROJECT_NAME" "$DATABASE" $SETUP_OPTIONS
fi

# Drop into an interactive AI session inside the new project (skipped when
# --one-off, JSON mode, non-TTY, or no AI agent configured).
ai_handoff "$PROJECT_NAME"

cd "$ORIG_DIR"
