#!/bin/bash
# Fastify framework hooks
#
# Fastify 5 (Node 20+; v4 is past end of life). `logger: true` still builds
# the default pino logger; a custom logger instance now goes in
# `loggerInstance`, and listen() only takes the options object used below.

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "Fastify project selected!"

    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "1.0.0",
  "description": "",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "dotenv": "^18.0.0",
    "fastify": "^5.12.0"
  }
}
EOF

    cat > server.js << 'EOF'
require('dotenv').config();
const fastify = require('fastify')({ logger: true });

const port = parseInt(process.env.PORT) || 3000;

fastify.get('/', async (request, reply) => {
    return {
        message: 'Hello from Fastify!',
        project: process.env.APP_NAME || 'my-project'
    };
});

const start = async () => {
    try {
        await fastify.listen({ port, host: '0.0.0.0' });
    } catch (err) {
        fastify.log.error(err);
        process.exit(1);
    }
};

start();
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Fastify project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Fastify project setup"
    fi

    echo-green "Fastify project structure created!"
}

framework_python_start_command() { echo ""; }

framework_node_start_command() {
    echo "node server.js"
}

framework_setup_env() {
    should_write_env ".env" || return 0
    echo-cyan "Setting up .env file ..."; echo-white

    local db_connection db_host db_port db_username db_password
    # SQLite overrides this with a FILE PATH; every server engine uses the name.
    local db_database="$DB_NAME"
    case $DATABASE_ENGINE in
        "sqlite"|"sqlite3")
            # The file MUST sit in the project directory: that is the only path
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

framework_run_migrations() { :; }

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
dist/
GITEOF

    echo-green ".gitignore created for Fastify project!"
}
