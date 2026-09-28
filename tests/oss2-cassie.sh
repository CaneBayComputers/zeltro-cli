#!/bin/bash -l
# OSS batch 2 — cassie, agent: codex

# Load NVM so codex is on PATH before ai-set runs
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.nvm/versions/node/v24.15.0/bin:$PATH"

mkdir -p /tmp/zeltro-tests/oss2-sessions
LOG=/tmp/zeltro-tests/oss2-master.log
ZELTRO="/usr/local/bin/zeltro"

$ZELTRO ai-set --agent codex
echo "AI agent set to: $(grep '^AI_AGENT=' /etc/zeltro-cli/.env)"

run_project() {
    local name="$1"
    local idea="$2"
    local logfile="/tmp/zeltro-tests/oss2-sessions/${name}.log"

    echo "[$(date '+%H:%M:%S')] === Starting: $name ===" | tee -a "$LOG"

    TERM=xterm $ZELTRO remove "$name" --force-db-delete > /dev/null 2>&1 || true

    timeout 2400 bash -l -c "export PATH=\"\$HOME/.nvm/versions/node/v24.15.0/bin:\$PATH\"; TERM=xterm $ZELTRO create --one-off \"$idea\" > \"$logfile\" 2>&1"
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

echo "=== OSS Batch 2 (cassie / codex) — $(date) ===" | tee "$LOG"
echo "Agent: $(grep '^AI_AGENT=' /etc/zeltro-cli/.env)" | tee -a "$LOG"
echo "" | tee -a "$LOG"

IDEA_PHOTOPRISM='Deploy PhotoPrism on this Zeltro server. The project name is photoprism — use this exact name, no changes.

PhotoPrism is an AI-powered photo management app (image: photoprism/photoprism:latest). It listens on port 2342. Use an nginx reverse proxy. Use the shared MariaDB (host=zeltro-mariadb, user=root, password=empty).

Steps:
1. mkdir -p ~/zeltro-projects/photoprism
2. Write docker-compose.yaml: photoprism-app service (env: PHOTOPRISM_AUTH_MODE=password, PHOTOPRISM_SITE_URL=http://photoprism/, PHOTOPRISM_ADMIN_USER=admin, PHOTOPRISM_ADMIN_PASSWORD=admin1234, PHOTOPRISM_DATABASE_DRIVER=mysql, PHOTOPRISM_DATABASE_SERVER=zeltro-mariadb:3306, PHOTOPRISM_DATABASE_NAME=photoprism, PHOTOPRISM_DATABASE_USER=root, PHOTOPRISM_DATABASE_PASSWORD=; persist /photoprism/originals and /photoprism/storage) + nginx (container_name=photoprism, static VPC IP). Write nginx.conf proxying to photoprism-app:2342 with client_max_body_size 500M.
3. cd ~/zeltro-projects/photoprism && zeltro setup photoprism --no-startup && zeltro up photoprism
4. curl -sI http://photoprism/ — expect 200 or 302. Default: admin/admin1234.'"$SUMMARY_SUFFIX"

IDEA_IMMICH='Deploy Immich on this Zeltro server. The project name is immich — use this exact name, no changes.

Immich is a self-hosted photo backup solution (image: ghcr.io/immich-app/immich-server:release). It listens on port 2283. Use an nginx reverse proxy. Use PostgreSQL with pgvecto.rs extension (image: tensorchord/pgvecto-rs:pg14-v0.2.0). Also needs Redis.

Steps:
1. mkdir -p ~/zeltro-projects/immich
2. Write docker-compose.yaml with THREE services: immich-server (image: ghcr.io/immich-app/immich-server:release, env: DB_HOSTNAME=immich-db, DB_USERNAME=postgres, DB_PASSWORD=postgres, DB_DATABASE_NAME=immich, REDIS_HOSTNAME=zeltro-redis; persist /usr/src/app/upload), immich-db (image: tensorchord/pgvecto-rs:pg14-v0.2.0, env: POSTGRES_USER=postgres, POSTGRES_PASSWORD=postgres, POSTGRES_DB=immich; persist /var/lib/postgresql/data), and nginx (container_name=immich, static VPC IP proxying to immich-server:2283).
3. cd ~/zeltro-projects/immich && zeltro setup immich --no-startup && zeltro up immich
4. Wait 30s, then curl -sI http://immich/ — expect 200. First user becomes admin.'"$SUMMARY_SUFFIX"

IDEA_TRILIUM='Deploy TriliumNext Notes on this Zeltro server. The project name is triliumnext — use this exact name, no changes.

TriliumNext is the maintained successor of Trilium Notes, a hierarchical note-taking app (image: ghcr.io/triliumnext/trilium:v0.104.1; the old zadam/trilium image is unmaintained). It listens on port 8080. Use an nginx reverse proxy. No database needed — uses SQLite.

Steps:
1. mkdir -p ~/zeltro-projects/triliumnext
2. Write docker-compose.yaml: triliumnext-app service (persist /home/node/trilium-data) + nginx (container_name=triliumnext, static VPC IP). Write nginx.conf proxying to triliumnext-app:8080.
3. cd ~/zeltro-projects/triliumnext && zeltro setup triliumnext --no-startup && zeltro up triliumnext
4. curl -sI the address zeltro status triliumnext prints — expect 200. Set password on first visit.'"$SUMMARY_SUFFIX"

IDEA_SEARXNG='Deploy SearXNG on this Zeltro server. The project name is searxng — use this exact name, no changes.

SearXNG is a privacy-respecting metasearch engine (image: searxng/searxng:latest). It listens on port 8080. Use an nginx reverse proxy. No database needed.

Steps:
1. mkdir -p ~/zeltro-projects/searxng
2. Write docker-compose.yaml: searxng-app service (env: SEARXNG_BASE_URL=http://searxng/) + nginx (container_name=searxng, static VPC IP). Write nginx.conf proxying to searxng-app:8080.
3. cd ~/zeltro-projects/searxng && zeltro setup searxng --no-startup && zeltro up searxng
4. curl -sI http://searxng/ — expect 200.'"$SUMMARY_SUFFIX"

IDEA_GLANCES='Deploy Glances on this Zeltro server. The project name is glances — use this exact name, no changes.

Glances is a cross-platform system monitoring tool (image: nicolargo/glances:latest-full). It listens on port 61208 in web server mode. Use an nginx reverse proxy. No database needed.

Steps:
1. mkdir -p ~/zeltro-projects/glances
2. Write docker-compose.yaml: glances-app service (env: GLANCES_OPT=-w; pid: host; volumes: /var/run/docker.sock:/var/run/docker.sock:ro) + nginx (container_name=glances, static VPC IP). Write nginx.conf proxying to glances-app:61208.
3. cd ~/zeltro-projects/glances && zeltro setup glances --no-startup && zeltro up glances
4. curl -sI http://glances/ — expect 200.'"$SUMMARY_SUFFIX"

IDEA_WGER='Deploy wger on this Zeltro server. The project name is wger — use this exact name, no changes.

wger is a workout/fitness manager (image: wger/server:latest). It listens on port 80 — no nginx proxy needed. Use PostgreSQL (host=zeltro-postgres, port=5432, user=root, password=password).

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE wger;"
2. mkdir -p ~/zeltro-projects/wger
3. Write docker-compose.yaml: single service, container_name=wger, static VPC IP. Env: DJANGO_DB_DATABASE=wger, DJANGO_DB_USER=root, DJANGO_DB_PASSWORD=password, DJANGO_DB_HOST=zeltro-postgres, DJANGO_DB_PORT=5432, SITE_URL=http://wger, DJANGO_SUPERUSER_USERNAME=admin, DJANGO_SUPERUSER_PASSWORD=admin1234, DJANGO_SUPERUSER_EMAIL=admin@example.com. Persist /home/wger/static and /home/wger/media.
4. cd ~/zeltro-projects/wger && zeltro setup wger --no-startup && zeltro up wger
5. Wait 30s, then curl -sI http://wger/ — expect 200 or 302.'"$SUMMARY_SUFFIX"

IDEA_MATTERMOST='Deploy Mattermost on this Zeltro server. The project name is mattermost — use this exact name, no changes.

Mattermost is a self-hosted team messaging platform (image: mattermost/mattermost-team-edition:latest). It listens on port 8065. Use an nginx reverse proxy. Use PostgreSQL (host=zeltro-postgres, port=5432, user=root, password=password).

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE mattermost;"
2. mkdir -p ~/zeltro-projects/mattermost
3. Write docker-compose.yaml: mattermost-app service (env: MM_SQLSETTINGS_DRIVERNAME=postgres, MM_SQLSETTINGS_DATASOURCE=postgres://root:password@zeltro-postgres:5432/mattermost?sslmode=disable, MM_SERVICESETTINGS_SITEURL=http://mattermost; persist /mattermost/config, /mattermost/data, /mattermost/logs, /mattermost/plugins) + nginx (container_name=mattermost, static VPC IP). Write nginx.conf proxying to mattermost-app:8065 (include WebSocket upgrade headers and client_max_body_size 50M).
4. cd ~/zeltro-projects/mattermost && zeltro setup mattermost --no-startup && zeltro up mattermost
5. Wait 20s, then curl -sI http://mattermost/ — expect 200 or 302.'"$SUMMARY_SUFFIX"

IDEA_OUTLINE='Deploy Outline on this Zeltro server. The project name is outline — use this exact name, no changes.

Outline is a team wiki and knowledge base (image: outlinewiki/outline:latest). It listens on port 3000. Use an nginx reverse proxy. Use PostgreSQL and Redis.

Steps:
1. Create DB: docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE outline;"
2. mkdir -p ~/zeltro-projects/outline
3. Write docker-compose.yaml: outline-app service (env: DATABASE_URL=postgres://root:password@zeltro-postgres:5432/outline, REDIS_URL=redis://zeltro-redis:6379, SECRET_KEY=any-32-hex-chars, UTILS_SECRET=any-32-hex-chars, URL=http://outline, PORT=3000, FILE_STORAGE=local, FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data; persist /var/lib/outline/data) + nginx (container_name=outline, static VPC IP). Write nginx.conf proxying to outline-app:3000.
4. cd ~/zeltro-projects/outline && zeltro setup outline --no-startup && zeltro up outline
5. curl -sI http://outline/ — expect 200 or 302.'"$SUMMARY_SUFFIX"

run_project "photoprism"  "$IDEA_PHOTOPRISM" &
run_project "immich"      "$IDEA_IMMICH" &
run_project "triliumnext" "$IDEA_TRILIUM" &
run_project "searxng"     "$IDEA_SEARXNG" &
run_project "glances"     "$IDEA_GLANCES" &
run_project "wger"        "$IDEA_WGER" &
run_project "mattermost"  "$IDEA_MATTERMOST" &
run_project "outline"     "$IDEA_OUTLINE" &

wait

echo "" | tee -a "$LOG"
echo "=== ALL DONE — $(date) ===" | tee -a "$LOG"
