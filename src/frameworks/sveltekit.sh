#!/bin/bash
# SvelteKit framework hooks#
# Serves on port 3000 inside the container. nginx runs in the same container and
# proxies 127.0.0.1:3000 with Upgrade headers already set, so websockets work
# without extra configuration. The dev server binds 127.0.0.1 explicitly:
# Vite 8 resolves "localhost" to ::1 in this image, which nginx never tries.#
# HMR clientPort is pinned to 80 (server.ws.clientPort; Vite 8.1 renamed it
# from server.hmr.clientPort, which now logs a deprecation). Vite defaults its
# HMR socket to the dev server's own port, but 3000 is never published — the
# browser reaches the app on port 80 through nginx. Without this the page loads
# and hot reload silently never connects.

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "SvelteKit project selected!"

    mkdir -p src/routes

    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite dev --port 3000",
    "build": "vite build",
    "preview": "vite preview --port 3000"
  },
  "devDependencies": {
    "@sveltejs/adapter-auto": "^7.0.0",
    "@sveltejs/kit": "^2.70.0",
    "@sveltejs/vite-plugin-svelte": "^7.3.0",
    "svelte": "^5.57.0",
    "vite": "^8.3.0"
  }
}
EOF

    cat > svelte.config.js << 'EOF'
import adapter from '@sveltejs/adapter-auto';

export default {
  kit: { adapter: adapter() },
};
EOF

    cat > vite.config.js << 'EOF'
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()],
  // nginx in this container proxies to 127.0.0.1:3000. Left at "localhost",
  // Vite 8 binds only ::1 here and nginx gets connection refused (502).
  // The browser reaches this app on port 80 through nginx; the dev server's own
  // port is never published, so the HMR socket has to be told where to connect.
  server: { host: '127.0.0.1', ws: { clientPort: 80 } },
});
EOF

    cat > src/app.html << 'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    %sveltekit.head%
  </head>
  <body>
    <div>%sveltekit.body%</div>
  </body>
</html>
EOF

    cat > src/routes/+page.svelte << 'EOF'
<main style="font-family: system-ui, sans-serif; padding: 3rem">
  <h1>Hello from SvelteKit</h1>
  <p>Edit <code>src/routes/+page.svelte</code> and this page reloads itself.</p>
</main>
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial SvelteKit project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial SvelteKit project setup"
    fi

    echo-green "SvelteKit project structure created!"
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
.svelte-kit/
build/
dist/
GITEOF

    echo-green ".gitignore created for SvelteKit project!"
}
