#!/bin/bash
# Next.js framework hooks#
# Serves on port 3000 inside the container. nginx runs in the same container and
# proxies 127.0.0.1:3000 with Upgrade headers already set, so websockets work
# without extra configuration and binding to localhost is sufficient.
#
# Next.js 16: Turbopack is the default for dev and build, and dev-only
# resources are blocked for any Origin not listed in allowedDevOrigins, which
# is why next.config.mjs allows the private IPv4 ranges (see the comment there).

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "Next.js project selected!"

    mkdir -p app

    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start -p 3000"
  },
  "dependencies": {
    "next": "^16.3.0",
    "react": "^19.3.0",
    "react-dom": "^19.3.0"
  }
}
EOF

    cat > next.config.mjs << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Next.js 16 refuses dev-only requests (the hot-reload websocket among them)
  // whose Origin is not localhost. The browser reaches this dev server by IP:
  // the container address, or the machine's LAN address and the project port.
  // Allow the private IPv4 ranges rather than one address, which changes when
  // the project is recreated or the machine moves networks.
  allowedDevOrigins: [
    '10.*.*.*',
    '192.168.*.*',
    ...Array.from({ length: 16 }, (_, i) => `172.${16 + i}.*.*`),
  ],
};

export default nextConfig;
EOF

    cat > app/layout.js << EOF
export const metadata = {
  title: '$PROJECT_NAME',
  description: 'Created with Zeltro',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
EOF

    cat > app/page.js << 'EOF'
export default function Home() {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: '3rem' }}>
      <h1>Hello from Next.js</h1>
      <p>Project: {process.env.APP_NAME || 'my-project'}</p>
      <p>Edit <code>app/page.js</code> and this page reloads itself.</p>
    </main>
  );
}
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Next.js project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Next.js project setup"
    fi

    echo-green "Next.js project structure created!"
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
.next/
out/
next-env.d.ts
GITEOF

    echo-green ".gitignore created for Next.js project!"
}
