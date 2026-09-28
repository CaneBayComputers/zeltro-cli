#!/bin/bash -l
# OSS batch 4 — dingdong, agent: claude

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"

mkdir -p /tmp/zeltro-tests/oss4-sessions
LOG=/tmp/zeltro-tests/oss4-master.log
ZELTRO="/usr/local/bin/zeltro"

run_project() {
    local name="$1"
    local idea="$2"
    local logfile="/tmp/zeltro-tests/oss4-sessions/${name}.log"

    echo "[$(date '+%H:%M:%S')] === Starting: $name ===" | tee -a "$LOG"

    TERM=xterm $ZELTRO remove "$name" --force-db-delete > /dev/null 2>&1 || true

    timeout 2400 bash -l -c "TERM=xterm $ZELTRO create --one-off \"$idea\" > \"$logfile\" 2>&1"
    local code=$?
    echo "EXIT:$code" >> "$logfile"

    # Probe the project's container IP. http://<name>/ resolves nowhere on the
    # host: Zeltro does not write /etc/hosts.
    local http_code projects_dir ip
    projects_dir=$(grep '^PROJECTS_DIR=' /etc/zeltro-cli/.env 2>/dev/null | cut -d= -f2- | tr -d '"')
    projects_dir="${projects_dir:-$HOME/zeltro-projects}"
    ip=$(grep -m1 'ipv4_address:' "$projects_dir/$name/docker-compose.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"')
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ip:-$name}/" 2>/dev/null)
    echo "[$(date '+%H:%M:%S')] DONE: $name | exit=$code | HTTP $http_code" | tee -a "$LOG"
}

SUMMARY_SUFFIX='

After the site is verified, create a file called SETUP_SUMMARY.md inside the project directory with exactly these sections:
## Project
[project name and Docker image used]
## Commands Run
[bulleted list of key commands you ran]
## Issues & Fixes
[any problems you hit and how you resolved them, or "None" if it went smoothly]
## Result
HTTP status: [e.g. 200 or 302]
URL: http://[project-name]/
Credentials: [default login/password if any, or "None required"]
## Verdict
[one sentence: did setup go smoothly or were there major problems?]'

echo "=== OSS Batch 4 (dingdong / claude) — $(date) ===" | tee "$LOG"
echo "" | tee -a "$LOG"

IDEA_OPENWEBUI='Deploy Open WebUI on this Zeltro server. The project name is open-webui — use this exact name, no changes.

Open WebUI is an AI chat interface (image: ghcr.io/open-webui/open-webui:main). It listens on port 8080. Use an nginx reverse proxy. No external database needed (uses SQLite internally).

Steps:
1. mkdir -p ~/zeltro-projects/open-webui
2. Write docker-compose.yaml: open-webui-app service (image: ghcr.io/open-webui/open-webui:main; env: WEBUI_SECRET_KEY=$(openssl rand -hex 32), ENABLE_OLLAMA_API=false, OLLAMA_BASE_URL=; volume: open-webui-data:/app/backend/data) + nginx service (container_name=open-webui, static VPC IP). Write nginx.conf proxying to open-webui-app:8080.
3. cd ~/zeltro-projects/open-webui && zeltro setup open-webui --no-startup && zeltro up open-webui
4. Wait 15 seconds, then curl -sI http://open-webui/ — expect 200 or 302.'"$SUMMARY_SUFFIX"

IDEA_YOURLS='Deploy YOURLS on this Zeltro server. The project name is yourls — use this exact name, no changes.

YOURLS is a self-hosted URL shortener (image: yourls/yourls). It serves on port 80 directly — no nginx proxy needed. Use the shared MariaDB (host=zeltro-mariadb, user=root, password=empty).

Steps:
1. Create DB: docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS yourls CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
2. mkdir -p ~/zeltro-projects/yourls
3. Write docker-compose.yaml: single service yourls-app (image: yourls/yourls; env: YOURLS_DB_HOST=zeltro-mariadb, YOURLS_DB_PORT=3306, YOURLS_DB_USER=root, YOURLS_DB_PASS=, YOURLS_DB_NAME=yourls, YOURLS_SITE=http://yourls, YOURLS_USER=admin, YOURLS_PASS=admin123; volume: yourls-data:/var/www/html/user/plugins; container_name=yourls, static VPC IP).
4. cd ~/zeltro-projects/yourls && zeltro setup yourls --no-startup && zeltro up yourls
5. Wait 20 seconds, then curl -sI http://yourls/ — expect 200 or 302.'"$SUMMARY_SUFFIX"

IDEA_MAUTIC='Deploy Mautic on this Zeltro server. The project name is mautic — use this exact name, no changes.

Mautic is a marketing automation platform (image: mautic/mautic:v5-apache). It serves on port 80 directly — no nginx proxy needed. Use the shared MariaDB (host=zeltro-mariadb, user=root, password=empty).

Steps:
1. Create DB: docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS mautic CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
2. mkdir -p ~/zeltro-projects/mautic
3. Write docker-compose.yaml: single service mautic-app (image: mautic/mautic:v5-apache; env: MAUTIC_DB_HOST=zeltro-mariadb, MAUTIC_DB_PORT=3306, MAUTIC_DB_USER=root, MAUTIC_DB_PASSWORD=, MAUTIC_DB_NAME=mautic; volumes: mautic-data:/var/www/html, mautic-logs:/var/www/html/var/logs; container_name=mautic, static VPC IP).
4. cd ~/zeltro-projects/mautic && zeltro setup mautic --no-startup && zeltro up mautic
5. Wait 30 seconds, then curl -sI http://mautic/ — expect 200 or 302. First visit shows the install wizard.'"$SUMMARY_SUFFIX"

IDEA_TOOLJET='Deploy Tooljet on this Zeltro server. The project name is tooljet — use this exact name, no changes.

Tooljet is a low-code app builder (image: tooljet/tooljet-ce:latest). It listens on port 3000. Use an nginx reverse proxy. Use the shared PostgreSQL (host=zeltro-postgres, port=5432, user=root, password=password).

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE tooljet_production;" 2>/dev/null || true
2. mkdir -p ~/zeltro-projects/tooljet
3. Write docker-compose.yaml: tooljet-app service (image: tooljet/tooljet-ce:latest; env: PG_HOST=zeltro-postgres, PG_PORT=5432, PG_DB=tooljet_production, PG_USER=root, PG_PASS=password, SECRET_KEY_BASE=$(openssl rand -hex 64), LOCKBOX_MASTER_KEY=$(openssl rand -hex 32), TOOLJET_HOST=http://tooljet, NODE_ENV=production; command: npm run start:prod) + nginx service (container_name=tooljet, static VPC IP). Write nginx.conf proxying to tooljet-app:3000.
4. cd ~/zeltro-projects/tooljet && zeltro setup tooljet --no-startup && zeltro up tooljet
5. Wait 60 seconds for DB migrations to complete, then curl -sI http://tooljet/ — expect 200 or 302. Default credentials: admin@example.com / password (set on first login).'"$SUMMARY_SUFFIX"

IDEA_BUDIBASE='Deploy Budibase on this Zeltro server. The project name is budibase — use this exact name, no changes.

Budibase is a low-code platform (image: budibase/budibase:latest). It serves on port 80 directly — no nginx proxy needed. No external database required (uses internal CouchDB).

Steps:
1. mkdir -p ~/zeltro-projects/budibase
2. Write docker-compose.yaml: single service budibase-app (image: budibase/budibase:latest; env: JWT_SECRET=$(openssl rand -hex 32), ENCRYPTION_KEY=$(openssl rand -hex 32), BB_ADMIN_USER_EMAIL=admin@example.com, BB_ADMIN_USER_PASSWORD=Budibase123!; volumes: budibase-data:/data; container_name=budibase, static VPC IP).
3. cd ~/zeltro-projects/budibase && zeltro setup budibase --no-startup && zeltro up budibase
4. Wait 20 seconds, then curl -sI http://budibase/ — expect 200 or 302.'"$SUMMARY_SUFFIX"

IDEA_PLAUSIBLE='Deploy Plausible Analytics on this Zeltro server. The project name is plausible — use this exact name, no changes.

Plausible is a privacy-first analytics platform (image: ghcr.io/plausible/community-edition:v2). It listens on port 8000. Use an nginx reverse proxy. It requires PostgreSQL and a Clickhouse database sidecar.

Steps:
1. Create PostgreSQL DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE plausible_db;" 2>/dev/null || true
2. mkdir -p ~/zeltro-projects/plausible
3. Write docker-compose.yaml with TWO app services:
   plausible-events-db service (image: clickhouse/clickhouse-server:23.3.7.5-alpine; volumes: plausible-events-data:/var/lib/clickhouse, plausible-events-logs:/var/log/clickhouse-server; no external port needed)
   plausible-app service (image: ghcr.io/plausible/community-edition:v2; depends_on: [plausible-events-db]; env: BASE_URL=http://plausible, SECRET_KEY_BASE=$(openssl rand -hex 64), DATABASE_URL=postgres://root:password@zeltro-postgres:5432/plausible_db, CLICKHOUSE_DATABASE_URL=http://plausible-events-db:8123/plausible_events_db, DISABLE_REGISTRATION=false)
   nginx service (container_name=plausible, static VPC IP). Write nginx.conf proxying to plausible-app:8000.
4. cd ~/zeltro-projects/plausible && zeltro setup plausible --no-startup && zeltro up plausible
5. Wait 30 seconds for migrations to complete, then curl -sI http://plausible/ — expect 200 or 302. Visit http://plausible/ to create first admin account.'"$SUMMARY_SUFFIX"

IDEA_PENPOT='Deploy Penpot on this Zeltro server. The project name is penpot — use this exact name, no changes.

Penpot is an open-source design tool. It has three services: frontend (penpotapp/frontend:latest, built-in nginx on port 80), backend (penpotapp/backend:latest, port 6060), and exporter (penpotapp/exporter:latest, port 6061). The frontend container is the entry point — assign the VPC IP and container_name to it. Use the shared PostgreSQL and Redis.

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE penpot;" 2>/dev/null || true
2. mkdir -p ~/zeltro-projects/penpot
3. Write docker-compose.yaml with THREE services:
   penpot-frontend service (image: penpotapp/frontend:latest; env: PENPOT_FLAGS=enable-registration enable-login disable-email-verification, PENPOT_BACKEND_URI=http://penpot-backend:6060, PENPOT_EXPORTER_URI=http://penpot-exporter:6061; container_name=penpot, static VPC IP)
   penpot-backend service (image: penpotapp/backend:latest; env: PENPOT_FLAGS=enable-registration enable-login disable-email-verification, PENPOT_PUBLIC_URI=http://penpot, PENPOT_DATABASE_URI=postgresql://root:password@zeltro-postgres:5432/penpot, PENPOT_DATABASE_USERNAME=root, PENPOT_DATABASE_PASSWORD=password, PENPOT_REDIS_URI=redis://zeltro-redis:6379/0, PENPOT_SECRET_KEY=$(openssl rand -hex 32), PENPOT_STORAGE_BACKEND=fs, PENPOT_STORAGE_FS_DIRECTORY=/opt/data/assets, PENPOT_SMTP_ENABLED=false, PENPOT_TELEMETRY_ENABLED=false; volumes: penpot-assets:/opt/data/assets)
   penpot-exporter service (image: penpotapp/exporter:latest; env: PENPOT_PUBLIC_URI=http://penpot, PENPOT_REDIS_URI=redis://zeltro-redis:6379/0)
4. cd ~/zeltro-projects/penpot && zeltro setup penpot --no-startup && zeltro up penpot
5. Wait 30 seconds, then curl -sI http://penpot/ — expect 200 or 302. Register at http://penpot/ to create the first account.'"$SUMMARY_SUFFIX"

IDEA_TYPEBOT='Deploy Typebot on this Zeltro server. The project name is typebot — use this exact name, no changes.

Typebot is a conversational form builder. It has two services: builder (baptistearno/typebot-builder:latest, port 3000) and viewer (baptistearno/typebot-viewer:latest, port 3001). Use an nginx reverse proxy routing / to builder:3000. Use the shared PostgreSQL (host=zeltro-postgres, port=5432, user=root, password=password).

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE typebot;" 2>/dev/null || true
2. mkdir -p ~/zeltro-projects/typebot
3. Write docker-compose.yaml:
   typebot-builder service (image: baptistearno/typebot-builder:latest; env: DATABASE_URL=postgresql://root:password@zeltro-postgres:5432/typebot, NEXTAUTH_URL=http://typebot, NEXTAUTH_SECRET=$(openssl rand -hex 32), NEXT_PUBLIC_VIEWER_URL=http://typebot, ENCRYPTION_SECRET=$(openssl rand -hex 16), ADMIN_EMAIL=admin@example.com, DEFAULT_WORKSPACE_PLAN=UNLIMITED)
   typebot-viewer service (image: baptistearno/typebot-viewer:latest; env: DATABASE_URL=postgresql://root:password@zeltro-postgres:5432/typebot, NEXTAUTH_URL=http://typebot, NEXT_PUBLIC_VIEWER_URL=http://typebot, ENCRYPTION_SECRET=<same as builder>)
   nginx service (container_name=typebot, static VPC IP). Write nginx.conf proxying all traffic to typebot-builder:3000.
4. cd ~/zeltro-projects/typebot && zeltro setup typebot --no-startup && zeltro up typebot
5. Wait 30 seconds for DB migrations, then curl -sI http://typebot/ — expect 200 or 302. Log in with admin@example.com.'"$SUMMARY_SUFFIX"

IDEA_NOCODB='Deploy NocoDB on this Zeltro server. The project name is nocodb — use this exact name, no changes.

NocoDB is an open-source Airtable alternative (image: nocodb/nocodb:latest). It listens on port 8080. Use an nginx reverse proxy. Use the shared PostgreSQL (host=zeltro-postgres, port=5432, user=root, password=password).

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE nocodb;" 2>/dev/null || true
2. mkdir -p ~/zeltro-projects/nocodb
3. Write docker-compose.yaml: nocodb-app service (image: nocodb/nocodb:latest; env: NC_DB=pg://zeltro-postgres:5432?u=root&p=password&d=nocodb, NC_AUTH_JWT_SECRET=$(openssl rand -hex 32); volumes: nocodb-data:/usr/app/data) + nginx service (container_name=nocodb, static VPC IP). Write nginx.conf proxying to nocodb-app:8080.
4. cd ~/zeltro-projects/nocodb && zeltro setup nocodb --no-startup && zeltro up nocodb
5. Wait 15 seconds, then curl -sI http://nocodb/ — expect 200 or 302. Default admin: admin@nocodb.com / Admin1234@ (set on first login).'"$SUMMARY_SUFFIX"

IDEA_MINIO='Deploy MinIO-compatible storage on this Zeltro server. The project name is minio — use this exact name, no changes.

MinIO has been archived and its images removed from Docker Hub and Quay, so use Silo, the maintained MinIO fork (image: pgsty/silo:RELEASE.2026-09-03T13-18-01Z). It keeps the MinIO command line, MINIO_ROOT_* variables and ports: the web console listens on port 9001; the S3 API is on port 9000. Use an nginx reverse proxy pointing to the console (port 9001). No external database needed.

Steps:
1. mkdir -p ~/zeltro-projects/minio
2. Write docker-compose.yaml: minio-app service (image: pgsty/silo:RELEASE.2026-09-03T13-18-01Z; command: server /data --console-address ":9001"; env: MINIO_ROOT_USER=minioadmin, MINIO_ROOT_PASSWORD=minioadmin123; volumes: minio-data:/data) + nginx service (container_name=minio, static VPC IP). Write nginx.conf proxying to minio-app:9001.
3. cd ~/zeltro-projects/minio && zeltro setup minio --no-startup && zeltro up minio
4. Wait 10 seconds, then curl -sI the address zeltro status minio prints — expect 200 or 302. Log in there with minioadmin / minioadmin123.'"$SUMMARY_SUFFIX"

run_project "open-webui" "$IDEA_OPENWEBUI" &
run_project "yourls"     "$IDEA_YOURLS" &
run_project "mautic"     "$IDEA_MAUTIC" &
run_project "tooljet"    "$IDEA_TOOLJET" &
run_project "budibase"   "$IDEA_BUDIBASE" &
run_project "plausible"  "$IDEA_PLAUSIBLE" &
run_project "penpot"     "$IDEA_PENPOT" &
run_project "typebot"    "$IDEA_TYPEBOT" &
run_project "nocodb"     "$IDEA_NOCODB" &
run_project "minio"      "$IDEA_MINIO" &

wait

echo "" | tee -a "$LOG"
echo "=== ALL DONE — $(date) ===" | tee -a "$LOG"
