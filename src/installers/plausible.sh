INSTALL_DISPLAY="Plausible Analytics"
INSTALL_NOTES="Privacy-first web analytics. First startup takes ~30 seconds for migrations. Create your account on first visit."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE plausible_db;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 64)

    mkdir -p clickhouse

    cat > clickhouse/ipv4-only.xml << 'EOF'
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOF

    cat > clickhouse/low-resources.xml << 'EOF'
<clickhouse>
    <mark_cache_size>536870912</mark_cache_size>
    <max_concurrent_queries>50</max_concurrent_queries>
    <max_server_memory_usage_to_ram_ratio>0.75</max_server_memory_usage_to_ram_ratio>
</clickhouse>
EOF

    cat > .env << EOF
BASE_URL=http://plausible
SECRET_KEY_BASE=$secret_key
TMPDIR=/var/lib/plausible/tmp
DATABASE_URL=postgres://root:password@zeltro-postgres:5432/plausible_db
CLICKHOUSE_DATABASE_URL=http://plausible-clickhouse:8123/plausible_events_db
MAILER_ADAPTER=Bamboo.LocalAdapter
DISABLE_REGISTRATION=false
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  plausible-clickhouse:
    image: clickhouse/clickhouse-server:24.3.3.102-alpine
    restart: unless-stopped
    volumes:
      - event-data:/var/lib/clickhouse
      - event-logs:/var/log/clickhouse-server
      - ./clickhouse/ipv4-only.xml:/etc/clickhouse-server/config.d/ipv4-only.xml:ro
      - ./clickhouse/low-resources.xml:/etc/clickhouse-server/config.d/low-resources.xml:ro
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 -O - http://127.0.0.1:8123/ping || exit 1"]
      start_period: 60s
      interval: 10s
      timeout: 5s
      retries: 12

  plausible-app:
    image: ghcr.io/plausible/community-edition:v2
    restart: unless-stopped
    command: sh -c "/entrypoint.sh db createdb && /entrypoint.sh db migrate && /entrypoint.sh run"
    env_file:
      - .env
    depends_on:
      plausible-clickhouse:
        condition: service_healthy
    volumes:
      - plausible-data:/var/lib/plausible
    ulimits:
      nofile:
        soft: 65535
        hard: 65535

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - plausible-app

volumes:
  event-data:
  event-logs:
  plausible-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://plausible-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 90;
    }
}
NGINX
}
