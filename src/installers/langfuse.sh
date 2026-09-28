INSTALL_DISPLAY="Langfuse"
INSTALL_CREDENTIALS="admin@example.com / admin123"
INSTALL_NOTES="Heavy stack: web + worker + ClickHouse + S3 storage (Silo, a MinIO fork). First boot runs ClickHouse migrations and can take 2-3 minutes."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE langfuse;" 2>/dev/null || true
}

write_files() {
    local salt encryption_key nextauth_secret

    salt=$(openssl rand -hex 32)
    encryption_key=$(openssl rand -hex 32)
    nextauth_secret=$(openssl rand -hex 32)

    cat > .env << EOF
DATABASE_URL=postgresql://root:password@zeltro-postgres:5432/langfuse
SALT=$salt
ENCRYPTION_KEY=$encryption_key
TELEMETRY_ENABLED=false
LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=false

CLICKHOUSE_MIGRATION_URL=clickhouse://clickhouse:9000
CLICKHOUSE_URL=http://clickhouse:8123
CLICKHOUSE_USER=clickhouse
CLICKHOUSE_PASSWORD=clickhouse
CLICKHOUSE_CLUSTER_ENABLED=false

REDIS_CONNECTION_STRING=redis://zeltro-redis:6379/6
LANGFUSE_BULLMQ_SKIP_REDIS_VERSION_CHECK=true

LANGFUSE_S3_EVENT_UPLOAD_BUCKET=langfuse
LANGFUSE_S3_EVENT_UPLOAD_REGION=auto
LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=minio
LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=miniosecret
LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=http://langfuse-minio:9000
LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true
LANGFUSE_S3_EVENT_UPLOAD_PREFIX=events/

LANGFUSE_S3_MEDIA_UPLOAD_BUCKET=langfuse
LANGFUSE_S3_MEDIA_UPLOAD_REGION=auto
LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID=minio
LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=miniosecret
LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT=http://langfuse-minio:9000
LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE=true
LANGFUSE_S3_MEDIA_UPLOAD_PREFIX=media/

NEXTAUTH_URL=http://langfuse
NEXTAUTH_SECRET=$nextauth_secret

LANGFUSE_INIT_ORG_ID=zeltro
LANGFUSE_INIT_ORG_NAME=Zeltro
LANGFUSE_INIT_PROJECT_ID=zeltro-project
LANGFUSE_INIT_PROJECT_NAME=Default
LANGFUSE_INIT_USER_EMAIL=admin@example.com
LANGFUSE_INIT_USER_NAME=Admin
LANGFUSE_INIT_USER_PASSWORD=admin123
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  langfuse-web:
    image: langfuse/langfuse:4.4.0
    restart: unless-stopped
    env_file: .env
    depends_on:
      clickhouse:
        condition: service_healthy
      langfuse-minio:
        condition: service_started

  langfuse-worker:
    image: langfuse/langfuse-worker:4.4.0
    restart: unless-stopped
    env_file: .env
    depends_on:
      clickhouse:
        condition: service_healthy
      langfuse-minio:
        condition: service_started

  clickhouse:
    image: clickhouse/clickhouse-server:25.12
    restart: unless-stopped
    user: "101:101"
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: clickhouse
      CLICKHOUSE_PASSWORD: clickhouse
    volumes:
      - langfuse-clickhouse-data:/var/lib/clickhouse
      - langfuse-clickhouse-logs:/var/log/clickhouse-server
    healthcheck:
      test: wget --no-verbose --tries=1 --spider http://localhost:8123/ping || exit 1
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 10s

  # Silo, the maintained MinIO fork: MinIO's own images are gone. Same S3 API,
  # MINIO_* variables and ports. Its binary is `silo`, so go through the
  # image's entrypoint, which maps `server` onto it.
  langfuse-minio:
    image: pgsty/silo:RELEASE.2026-09-03T13-18-01Z
    restart: unless-stopped
    entrypoint: sh
    command: -c 'mkdir -p /data/langfuse && exec docker-entrypoint.sh server --address ":9000" --console-address ":9001" /data'
    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: miniosecret
    volumes:
      - langfuse-minio-data:/data

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - langfuse-web

volumes:
  langfuse-clickhouse-data:
  langfuse-clickhouse-logs:
  langfuse-minio-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 256M;
    location / {
        proxy_pass http://langfuse-web:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }
}
NGINX
}
