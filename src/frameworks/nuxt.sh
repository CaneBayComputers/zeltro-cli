#!/bin/bash
# Nuxt framework hooks#
# Serves on port 3000 inside the container. nginx runs in the same container and
# proxies 127.0.0.1:3000 with Upgrade headers already set, so websockets work
# without extra configuration and binding to localhost is sufficient.#
# HMR clientPort is pinned to 80 (server.ws.clientPort; Vite 8.1 renamed it
# from server.hmr.clientPort, which now logs a deprecation). Vite defaults its
# HMR socket to the dev server's own port, but 3000 is never published — the
# browser reaches the app on port 80 through nginx. Without this the page loads
# and hot reload silently never connects.#
# Nuxt needs two things the other dev servers do not.
#
# --no-fork: by default `nuxt dev` forks a child Vite process and proxies to it
# over a unix socket in /tmp. Under supervisor that child does not survive a
# restart, and the parent then answers every request with 500 (connect ENOENT
# .../nuxt.sock).
#
# The rm -rf in the dev script: if Nuxt is interrupted during dependency
# pre-bundling -- which happens routinely here, because supervisor starts the
# app while npm install is still running -- it leaves a half-written .nuxt cache
# and never recovers from it on any later boot. Clearing at start makes every
# launch deterministic. It costs a few seconds of re-bundling; the alternative
# is a project that returns 500 forever after one unlucky start.

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "Nuxt project selected!"

    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "rm -rf .nuxt node_modules/.vite && nuxt dev --port 3000 --no-fork",
    "build": "nuxt build",
    "preview": "nuxt preview"
  },
  "dependencies": {
    "nuxt": "^4.5.0",
    "vue": "^3.5.40",
    "vue-router": "^5.3.0"
  }
}
EOF

    cat > nuxt.config.ts << 'EOF'
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  // The browser reaches this app on port 80 through nginx; the dev server's own
  // port is never published, so the HMR socket has to be told where to connect.
  vite: { server: { ws: { clientPort: 80 } } },
});
EOF

    # Nuxt 4 keeps application code under app/ (srcDir). A root-level app.vue
    # is still auto-detected for upgraded projects, but new ones use app/.
    mkdir -p app

    cat > app/app.vue << 'EOF'
<template>
  <main style="font-family: system-ui, sans-serif; padding: 3rem">
    <h1>Hello from Nuxt</h1>
    <p>Edit <code>app/app.vue</code> and this page reloads itself.</p>
  </main>
</template>
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Nuxt project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Nuxt project setup"
    fi

    echo-green "Nuxt project structure created!"
}

framework_node_start_command() {
    echo "npm run dev"
}

framework_python_start_command() { echo ""; }

framework_setup_env() {
    should_write_env ".env" || return 0
    echo-cyan "Setting up .env file ..."; echo-white

    local db_connection db_host db_port db_username db_password
    local db_database="$DB_NAME"
    case $DATABASE_ENGINE in
        "sqlite"|"sqlite3")
            # Must live in the project directory: that is the only path
            # bind-mounted into the container, so a database anywhere else is
            # destroyed when the container is recreated on `zeltro up`.
            db_connection="sqlite"; db_host=""; db_port=""
            db_username=""; db_password=""
            db_database="/usr/share/nginx/html/${FRAMEWORK_SQLITE_PATH:-database.sqlite}"
            ;;
        "postgres"|"postgresql"|"pgsql")
            db_connection="postgresql"; db_host="$POSTGRES_CONTAINER_NAME"; db_port="5432"
            db_username="root"; db_password="password"
            ;;
        "mongo"|"mongodb")
            db_connection="mongodb"; db_host="$MONGO_CONTAINER_NAME"; db_port="27017"
            db_username="root"; db_password="password"
            ;;
        *)
            db_connection="mysql"; db_host="$MARIADB_CONTAINER_NAME"; db_port="3306"
            db_username="root"; db_password=""
            ;;
    esac

    cat > .env << EOF
APP_NAME=$PROJECT_NAME
APP_ENV=local
APP_DEBUG=true
APP_URL=http://$PROJECT_NAME
PORT=3000
DB_CONNECTION=$db_connection
DB_HOST=$db_host
DB_PORT=$db_port
DB_DATABASE=$db_database
DB_USERNAME=$db_username
DB_PASSWORD=$db_password
REDIS_HOST=$REDIS_CONTAINER_NAME
REDIS_PORT=6379
MAIL_HOST=$MAILHOG_CONTAINER_NAME
MAIL_PORT=1025
EOF

    echo-green "The .env file has been created!"; echo-white
}

framework_run_migrations() {
    # No built-in migration runner — bring Prisma, Drizzle or Knex if you want one
    :
}

framework_setup_gitignore() {
    [ -f ".gitignore" ] && {
        if ! grep -q "docker-compose.yaml" .gitignore; then
            printf '\n# Docker infrastructure\ndocker-compose.yaml\n' >> .gitignore
        fi
        return
    }

    cat > .gitignore << 'GITEOF'
docker-compose.yaml
node_modules/
.env
*.log
.DS_Store
.nuxt/
.output/
dist/
GITEOF

    echo-green ".gitignore created for Nuxt project!"
}
