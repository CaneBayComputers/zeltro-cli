#!/bin/bash
# NestJS framework hooks
#
# NestJS 12 ships ESM-only packages, so the scaffold is an ESM project like the
# official starter: "type": "module", nodenext resolution, and relative imports
# spelled with a .js extension (./app.module.js), which TypeScript maps back to
# the .ts source. The app runs on Node 20.19+/22.12+; the CLI's schematics ask
# for Node 22.22.3+ and only warn (EBADENGINE) on older Node 22 releases.

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_IS_NODE=1
FRAMEWORK_DOCKER_TEMPLATE="node-project"

framework_scaffold() {
    echo-return; echo-cyan "NestJS project selected!"

    mkdir -p src

    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "description": "",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "nest build",
    "start": "nest start",
    "start:dev": "nest start --watch",
    "start:prod": "node dist/main"
  },
  "dependencies": {
    "@nestjs/common": "^12.1.0",
    "@nestjs/core": "^12.1.0",
    "@nestjs/platform-express": "^12.1.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1"
  },
  "devDependencies": {
    "@nestjs/cli": "^12.0.0",
    "@nestjs/schematics": "^12.0.0",
    "@types/node": "^22.0.0",
    "typescript": "^6.0.2"
  }
}
EOF

    # Matches the official v12 starter (nestjs/typescript-starter): ESM with
    # nodenext resolution. TypeScript 6 no longer loads every @types package by
    # default, so "types" has to name node or process.env stops type-checking.
    cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "resolvePackageJsonExports": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "declaration": true,
    "removeComments": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "allowSyntheticDefaultImports": true,
    "target": "ES2023",
    "sourceMap": true,
    "outDir": "./dist",
    "incremental": true,
    "skipLibCheck": true,
    "strict": true,
    "strictPropertyInitialization": false,
    "types": ["node"]
  }
}
EOF

    # nest build/start compile with this file when it exists. TypeScript 6
    # defaults rootDir to the tsconfig's own directory and refuses to build
    # (TS5011) unless it is set, so it pins rootDir to src and dist/main.js
    # stays where start:prod expects it.
    cat > tsconfig.build.json << 'EOF'
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "rootDir": "./src"
  },
  "include": ["src"],
  "exclude": ["node_modules", "test", "dist", "**/*spec.ts"]
}
EOF

    cat > nest-cli.json << 'EOF'
{
  "$schema": "https://json.schemastore.org/nest-cli",
  "collection": "@nestjs/schematics",
  "sourceRoot": "src",
  "compilerOptions": {
    "deleteOutDir": true
  }
}
EOF

    cat > src/main.ts << 'EOF'
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';

async function bootstrap() {
    const app = await NestFactory.create(AppModule);
    const port = parseInt(process.env.PORT ?? '3000', 10);
    await app.listen(port, '0.0.0.0');
    console.log(`Application is running on port ${port}`);
}
await bootstrap();
EOF

    cat > src/app.module.ts << 'EOF'
import { Module } from '@nestjs/common';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';

@Module({
    imports: [],
    controllers: [AppController],
    providers: [AppService],
})
export class AppModule {}
EOF

    cat > src/app.controller.ts << 'EOF'
import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service.js';

@Controller()
export class AppController {
    constructor(private readonly appService: AppService) {}

    @Get()
    getHello() {
        return this.appService.getHello();
    }
}
EOF

    cat > src/app.service.ts << 'EOF'
import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
    getHello() {
        return {
            message: 'Hello from NestJS!',
            project: process.env.APP_NAME || 'my-project',
        };
    }
}
EOF

    cat > start.sh << 'EOF'
#!/bin/sh
# npm's own rollback can fail with ENOTEMPTY on overlayfs when an install is
# interrupted or the host is loaded, leaving node_modules half-written and
# unrecoverable in place. Retry once from a clean slate rather than letting the
# container die -- nest's dependency tree is by far the heaviest here.
if [ ! -d node_modules ]; then
    npm install --no-audit --no-fund || {
        echo "npm install failed; clearing node_modules and retrying once ..."
        rm -rf node_modules
        npm install --no-audit --no-fund
    }
fi
npm run start
EOF
    chmod +x start.sh

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial NestJS project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial NestJS project setup"
    fi

    echo-green "NestJS project structure created!"
}

framework_python_start_command() { echo ""; }

framework_node_start_command() {
    echo "sh start.sh"
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
dist/
.env
*.log
.DS_Store
GITEOF

    echo-green ".gitignore created for NestJS project!"
}
