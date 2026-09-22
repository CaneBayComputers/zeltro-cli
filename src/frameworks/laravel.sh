#!/bin/bash
# Laravel framework hooks

FRAMEWORK_SQLITE_PATH="database/database.sqlite"
FRAMEWORK_IS_PYTHON=0
FRAMEWORK_DOCKER_TEMPLATE="project"

framework_scaffold() {
    if [[ "$NEW_PROJECT_FORCE_FORK" == "1" && -n "$LARAVEL_REPOSITORY_URL" ]]; then
        if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
            echo-return; echo-cyan "Forking Laravel starter repository on GitHub and cloning your fork..."

            cd "$PROJECTS_DIR"
            if [ -d "$PROJECT_NAME" ] && [ -z "$(ls -A "$PROJECT_NAME" 2>/dev/null)" ]; then
                rmdir "$PROJECT_NAME" 2>/dev/null || rm -rf "$PROJECT_NAME"
            fi

            if [[ "$JSON_OUTPUT" == "1" ]]; then
                if gh repo fork "$LARAVEL_REPOSITORY_URL" --clone > /dev/null 2>&1; then FORK_USED=1
                else echo-yellow "GitHub fork failed; falling back to standard Laravel download."; fi
            else
                if gh repo fork "$LARAVEL_REPOSITORY_URL" --clone; then FORK_USED=1
                else echo-yellow "GitHub fork failed; falling back to standard Laravel download."; fi
            fi

            if [[ "$FORK_USED" -eq 1 ]]; then
                FORK_DIR_NAME=$(basename -s .git "$LARAVEL_REPOSITORY_URL")
                [ -z "$FORK_DIR_NAME" ] && FORK_DIR_NAME="$PROJECT_NAME"
                [ "$FORK_DIR_NAME" != "$PROJECT_NAME" ] && [ -d "$FORK_DIR_NAME" ] && mv "$FORK_DIR_NAME" "$PROJECT_NAME"

                if [ -d "$PROJECT_NAME/.git" ]; then
                    cd "$PROJECT_NAME"
                    ORIGINAL_REMOTE_NAME=$(basename -s .git "$LARAVEL_REPOSITORY_URL")
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        ORIGINAL_REMOTE_NAME=$(echo "$ORIGINAL_REMOTE_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr ' ' '-' | LC_ALL=C tr -cd 'a-z0-9-_.')
                    else
                        ORIGINAL_REMOTE_NAME=$(echo "$ORIGINAL_REMOTE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-_.')
                    fi
                    [ -z "$ORIGINAL_REMOTE_NAME" ] && ORIGINAL_REMOTE_NAME="upstream"
                    if git remote get-url upstream >/dev/null 2>&1; then
                        if ! git remote get-url "$ORIGINAL_REMOTE_NAME" >/dev/null 2>&1; then
                            git remote rename upstream "$ORIGINAL_REMOTE_NAME" >/dev/null 2>&1 || true
                        fi
                    fi
                    cd "$PROJECTS_DIR"
                    echo-yellow "Note: GitHub controls fork visibility; forks are typically public by default."
                fi
            fi

            cd "$PROJECTS_DIR/$PROJECT_NAME"
        else
            echo-yellow "GitHub CLI not available. Downloading Laravel skeleton without forking."
        fi
    fi

    if [[ "$FORK_USED" -ne 1 ]]; then
        debug "Starting Laravel download for version: $CUR_LARAVEL_BRANCH"
        echo-return; echo-cyan "Downloading Laravel project..."

        if [[ "$JSON_OUTPUT" == "1" ]]; then
            if ! curl -sL "https://github.com/laravel/laravel/archive/refs/tags/${CUR_LARAVEL_BRANCH}.tar.gz" | tar -xz --strip-components=1 > /dev/null 2>&1; then
                echo "{\"action\":\"new_project\",\"project_name\":\"$PROJECT_NAME\",\"framework\":\"laravel\",\"status\":\"error\",\"error\":\"download_failed\",\"details\":\"Failed to download Laravel ${CUR_LARAVEL_BRANCH}\"}"
                exit 1
            fi
        else
            curl -L "https://github.com/laravel/laravel/archive/refs/tags/${CUR_LARAVEL_BRANCH}.tar.gz" | tar -xz --strip-components=1
        fi

        echo-green "Laravel project structure created!"
    fi
}

framework_python_start_command() { echo ""; }

framework_setup_env() {
    should_write_env ".env" || return 0
    [ ! -f ".env.example" ] && return
    echo-cyan "Setting up .env file ..."; echo-white
    cp -f .env.example .env

    APP_KEY="base64:$(head -c 32 /dev/urandom | base64)"
    zeltro-sed-change "/^#*\s*APP_NAME=/" "APP_NAME=$PROJECT_NAME" .env
    zeltro-sed-change "/^#*\s*APP_KEY=/" "APP_KEY=$APP_KEY" .env
    zeltro-sed-change "/^#*\s*APP_ENV=/" "APP_ENV=local" .env
    zeltro-sed-change "/^#*\s*APP_DEBUG=/" "APP_DEBUG=true" .env
    zeltro-sed-change "/^#*\s*APP_URL=/" "APP_URL=http://$PROJECT_NAME" .env

    case $DATABASE_ENGINE in
        "sqlite"|"sqlite3")
            # Laravel wants an absolute path (or it resolves database/database.sqlite).
            # The file MUST live in the project directory — that is the only path
            # bind-mounted into the container, so a database anywhere else is
            # destroyed when the container is recreated on `zeltro up`.
            # Laravel errors out if the file does not exist, so ensure_database
            # creates it before migrations run.
            zeltro-sed-change "/^#*\s*DB_CONNECTION=/" "DB_CONNECTION=sqlite" .env
            zeltro-sed-change "/^#*\s*DB_HOST=/" "DB_HOST=" .env
            zeltro-sed-change "/^#*\s*DB_PORT=/" "DB_PORT=" .env
            zeltro-sed-change "/^#*\s*DB_DATABASE=/" "DB_DATABASE=/usr/share/nginx/html/${FRAMEWORK_SQLITE_PATH:-database/database.sqlite}" .env
            zeltro-sed-change "/^#*\s*DB_USERNAME=/" "DB_USERNAME=" .env
            zeltro-sed-change "/^#*\s*DB_PASSWORD=/" "DB_PASSWORD=" .env
            ;;
        "postgres"|"postgresql"|"pgsql")
            zeltro-sed-change "/^#*\s*DB_CONNECTION=/" "DB_CONNECTION=pgsql" .env
            zeltro-sed-change "/^#*\s*DB_HOST=/" "DB_HOST=$POSTGRES_CONTAINER_NAME" .env
            zeltro-sed-change "/^#*\s*DB_PORT=/" "DB_PORT=5432" .env
            zeltro-sed-change "/^#*\s*DB_DATABASE=/" "DB_DATABASE=$DB_NAME" .env
            zeltro-sed-change "/^#*\s*DB_USERNAME=/" "DB_USERNAME=root" .env
            zeltro-sed-change "/^#*\s*DB_PASSWORD=/" "DB_PASSWORD=password" .env
            ;;
        "mongodb")
            zeltro-sed-change "/^#*\s*DB_CONNECTION=/" "DB_CONNECTION=mongodb" .env
            zeltro-sed-change "/^#*\s*DB_HOST=/" "DB_HOST=$MONGO_CONTAINER_NAME" .env
            zeltro-sed-change "/^#*\s*DB_PORT=/" "DB_PORT=27017" .env
            zeltro-sed-change "/^#*\s*DB_DATABASE=/" "DB_DATABASE=$DB_NAME" .env
            zeltro-sed-change "/^#*\s*DB_USERNAME=/" "DB_USERNAME=root" .env
            zeltro-sed-change "/^#*\s*DB_PASSWORD=/" "DB_PASSWORD=password" .env
            ;;
        *)
            zeltro-sed-change "/^#*\s*DB_CONNECTION=/" "DB_CONNECTION=mysql" .env
            zeltro-sed-change "/^#*\s*DB_HOST=/" "DB_HOST=$MARIADB_CONTAINER_NAME" .env
            zeltro-sed-change "/^#*\s*DB_PORT=/" "DB_PORT=3306" .env
            zeltro-sed-change "/^#*\s*DB_DATABASE=/" "DB_DATABASE=$DB_NAME" .env
            zeltro-sed-change "/^#*\s*DB_USERNAME=/" "DB_USERNAME=root" .env
            zeltro-sed-change "/^#*\s*DB_PASSWORD=/" "DB_PASSWORD=" .env
            ;;
    esac

    zeltro-sed-change "/^#*\s*CACHE_DRIVER=/" "CACHE_DRIVER=redis" .env
    zeltro-sed-change "/^#*\s*SESSION_DRIVER=/" "SESSION_DRIVER=redis" .env
    zeltro-sed-change "/^#*\s*QUEUE_CONNECTION=/" "QUEUE_CONNECTION=redis" .env
    zeltro-sed-change "/^#*\s*CACHE_STORE=/" "CACHE_STORE=redis" .env
    zeltro-sed-change "/^#*\s*CACHE_PREFIX=/" "CACHE_PREFIX=$PROJECT_NAME" .env
    zeltro-sed-change "/^#*\s*MEMCACHED_HOST=/" "MEMCACHED_HOST=$MEMCACHED_CONTAINER_NAME" .env
    zeltro-sed-change "/^#*\s*REDIS_HOST=/" "REDIS_HOST=$REDIS_CONTAINER_NAME" .env
    zeltro-sed-change "/^#*\s*MAIL_MAILER=/" "MAIL_MAILER=smtp" .env
    zeltro-sed-change "/^#*\s*MAIL_HOST=/" "MAIL_HOST=$MAILHOG_CONTAINER_NAME" .env
    zeltro-sed-change "/^#*\s*MAIL_PORT=/" "MAIL_PORT=1025" .env
    zeltro-sed-change "/^#*\s*MAIL_USERNAME=/" "MAIL_USERNAME=null" .env
    zeltro-sed-change "/^#*\s*MAIL_PASSWORD=/" "MAIL_PASSWORD=null" .env
    zeltro-sed-change "/^#*\s*MAIL_ENCRYPTION=/" "MAIL_ENCRYPTION=null" .env
    zeltro-sed-change "/^#*\s*MAIL_FROM_ADDRESS=/" "MAIL_FROM_ADDRESS=\"hello@$PROJECT_NAME.local\"" .env
    zeltro-sed-change "/^#*\s*MAIL_FROM_NAME=/" "MAIL_FROM_NAME=\"$PROJECT_NAME\"" .env

    # Propagate AWS credentials if available
    local aws_key="" aws_secret="" aws_region=""
    if command -v aws >/dev/null 2>&1; then
        aws_key=$(aws configure get aws_access_key_id 2>/dev/null || true)
        aws_secret=$(aws configure get aws_secret_access_key 2>/dev/null || true)
        aws_region=$(aws configure get region 2>/dev/null || true)
    fi
    if [[ -z "$aws_key" || -z "$aws_secret" ]] && [[ -f "$HOME/.aws/credentials" ]]; then
        aws_key=$(awk '/^\[default\]/{f=1;next}/^\[/{f=0}f && /aws_access_key_id/{print $3}' "$HOME/.aws/credentials" 2>/dev/null | head -1 || true)
        aws_secret=$(awk '/^\[default\]/{f=1;next}/^\[/{f=0}f && /aws_secret_access_key/{print $3}' "$HOME/.aws/credentials" 2>/dev/null | head -1 || true)
    fi
    if [[ -z "$aws_region" ]] && [[ -f "$HOME/.aws/config" ]]; then
        aws_region=$(awk '/^\[default\]/{f=1;next}/^\[/{f=0}f && /region/{print $3}' "$HOME/.aws/config" 2>/dev/null | head -1 || true)
    fi
    [[ -n "$aws_key" ]]    && zeltro-sed-change "/^#*\s*AWS_ACCESS_KEY_ID=/" "AWS_ACCESS_KEY_ID=$aws_key" .env
    [[ -n "$aws_secret" ]] && zeltro-sed-change "/^#*\s*AWS_SECRET_ACCESS_KEY=/" "AWS_SECRET_ACCESS_KEY=$aws_secret" .env
    [[ -n "$aws_region" ]] && zeltro-sed-change "/^#*\s*AWS_DEFAULT_REGION=/" "AWS_DEFAULT_REGION=$aws_region" .env
    echo "" >> .env
    echo "XDG_CONFIG_HOME=/usr/share/nginx/html/storage/app" >> .env

    echo-green "The .env file has been created!"; echo-white
}

framework_run_migrations() {
    [ ! -f "artisan" ] && return

    # Adopting an existing app (MIGRATE_SAFE=1): apply pending migrations only —
    # non-destructive, no data loss, no seed. Greenfield: full reset + seed.
    if [ "${MIGRATE_SAFE:-0}" = "1" ]; then
        echo-cyan 'Applying pending migrations (artisan migrate) ...'; echo-white
        # A failure used to be swallowed by `|| true` and followed by a green
        # "Migrations applied" -- a stack trace, then a success message. Report it,
        # but don't abort: the container is already up and still useful.
        local _mig_ok=0
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            art-docker migrate --force > /dev/null 2>&1 && _mig_ok=1
        else
            art-docker migrate --force && _mig_ok=1
        fi
        if [ "$_mig_ok" = "1" ]; then
            echo-green 'Migrations applied (existing data and seeders left untouched).'; echo-white
        else
            echo-red "Migrations FAILED -- see the output above. The project is up; fix the"
            echo-red "cause, then run: zeltro art migrate"
            echo-yellow "Common cause: the .env DB_HOST/DB_DATABASE do not match Zeltro's shared services"
            echo-yellow "(re-run setup with --overwrite-env to point them there)."; echo-white
        fi
        return
    fi

    echo-cyan 'Running migrations ...'; echo-white

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        art-docker migrate:fresh > /dev/null 2>&1 && MIGRATE_SUCCESS=0 || MIGRATE_SUCCESS=$?
    else
        art-docker migrate:fresh; MIGRATE_SUCCESS=$?
    fi

    if [ $MIGRATE_SUCCESS -eq 0 ]; then
        echo-green 'Migrations successful'; echo-white
        echo-cyan 'Seeding database ...'; echo-white
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            art-docker db:seed > /dev/null 2>&1 || true
        else
            art-docker db:seed || true
        fi
        echo-green 'Database seeded!'; echo-white
    fi
}

framework_setup_gitignore() {
    if [ ! -f ".gitignore" ]; then
        cat > .gitignore << 'GITEOF'
/node_modules
/public/hot
/public/storage
/storage/*.key
/vendor
.env
.env.backup
.env.production
.phpunit.result.cache
Homestead.json
Homestead.yaml
npm-debug.log
yarn-error.log
/.fleet
/.idea
/.vscode
GITEOF
    fi
    if ! grep -q "docker-compose.yaml" .gitignore; then
        printf '\n# Docker infrastructure\ndocker-compose.yaml\n' >> .gitignore
        echo-green "Added docker-compose.yaml to .gitignore"
    fi
}
