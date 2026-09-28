#!/bin/bash
# Astro framework hooks#
# Serves on port 3000 inside the container. nginx runs in the same container and
# proxies 127.0.0.1:3000 with Upgrade headers already set, so websockets work
# without extra configuration. The dev server binds 127.0.0.1 explicitly:
# Vite 8 resolves "localhost" to ::1 in this image, which nginx never tries.#
# HMR clientPort is pinned to 80 (server.ws.clientPort; Vite 8.1 renamed it
# from server.hmr.clientPort, which now logs a deprecation). Vite defaults its
# HMR socket to the dev server's own port, but 3000 is never published — the
# browser reaches the app on port 80 through nginx. Without this the page loads
# and hot reload silently never connects.
#
# --ignore-lock: Astro 7 writes .astro/dev.json with the dev server's PID and
# refuses to start while that PID looks alive. The file lives in the
# bind-mounted project, so it survives a container restart, and in the new
# container the old PID can belong to another process; the dev server then
# exits with "Another astro dev server is already running" until supervisor's
# retries happen to land on a free PID. Supervisor already guarantees there is
# only one dev server per container, so the lock adds nothing here.

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "Astro project selected!"

    mkdir -p src/pages

    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "astro dev --port 3000 --ignore-lock",
    "build": "astro build",
    "preview": "astro preview --port 3000"
  },
  "dependencies": {
    "astro": "^7.3.5"
  }
}
EOF

    cat > astro.config.mjs << 'EOF'
import { defineConfig } from 'astro/config';

export default defineConfig({
  // nginx in this container proxies to 127.0.0.1:3000. Left at "localhost",
  // Vite 8 binds only ::1 here and nginx gets connection refused (502).
  server: { port: 3000, host: '127.0.0.1' },
  // The browser reaches this app on port 80 through nginx; the dev server's own
  // port is never published, so the HMR socket has to be told where to connect.
  vite: { server: { ws: { clientPort: 80 } } },
});
EOF

    cat > src/pages/index.astro << 'EOF'
---
const project = import.meta.env.APP_NAME || 'my-project';
---
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{project}</title>
  </head>
  <body>
    <main style="font-family: system-ui, sans-serif; padding: 3rem">
      <h1>Hello from Astro</h1>
      <p>Edit <code>src/pages/index.astro</code> and this page reloads itself.</p>
    </main>
  </body>
</html>
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Astro project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Astro project setup"
    fi

    echo-green "Astro project structure created!"
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
.astro/
dist/
GITEOF

    echo-green ".gitignore created for Astro project!"
}
