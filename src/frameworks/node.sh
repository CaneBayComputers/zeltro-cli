#!/bin/bash
# Plain Node.js framework hooks

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "Node.js project selected!"

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
    "dotenv": "^18.0.0"
  }
}
EOF

    cat > server.js << 'EOF'
require('dotenv').config();
const http = require('http');

const port = parseInt(process.env.PORT) || 3000;

const server = http.createServer((req, res) => {
    if (req.url === '/') {
        if (req.method === 'HEAD') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end();
        } else {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                message: 'Hello from Node.js!',
                project: process.env.APP_NAME || 'my-project'
            }));
        }
    } else {
        res.writeHead(404);
        res.end();
    }
});

server.listen(port, '0.0.0.0', () => {
    console.log(`Server running on 0.0.0.0:${port}`);
});
EOF

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Node.js project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Node.js project setup"
    fi

    echo-green "Node.js project structure created!"
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

    echo-green ".gitignore created for Node.js project!"
}
