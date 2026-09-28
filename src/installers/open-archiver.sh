INSTALL_DISPLAY="Open Archiver"
INSTALL_CREDENTIALS="Create the first admin account on first visit"
INSTALL_NOTES="Connect an IMAP / Google Workspace / M365 mailbox under Ingestion Sources to start archiving."

# First boot runs Drizzle migrations and waits for Meilisearch.
INSTALL_READY_RETRIES=24

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"open_archiver\";" 2>/dev/null || true
}

write_files() {
    local jwt_secret encryption_key meili_key

    jwt_secret=$(openssl rand -hex 32)
    encryption_key=$(openssl rand -hex 32)
    meili_key=$(openssl rand -hex 16)

    cat > docker-compose.yaml << EOF
services:
  open-archiver-app:
    image: logiclabshq/open-archiver:v0.5.2
    restart: unless-stopped
    environment:
      NODE_ENV: production
      PORT_FRONTEND: "3000"
      PORT_BACKEND: "4000"
      APP_URL: http://open-archiver
      ORIGIN: http://open-archiver
      SYNC_FREQUENCY: "* * * * *"
      DATABASE_URL: "postgresql://root:password@zeltro-postgres:5432/open_archiver"
      MEILI_HOST: http://open-archiver-meilisearch:7700
      MEILI_MASTER_KEY: "$meili_key"
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      REDIS_TLS_ENABLED: "false"
      STORAGE_TYPE: local
      STORAGE_LOCAL_ROOT_PATH: /var/data/open-archiver
      BODY_SIZE_LIMIT: 100M
      JWT_SECRET: "$jwt_secret"
      JWT_EXPIRES_IN: 7d
      ENCRYPTION_KEY: "$encryption_key"
      ENABLE_DELETION: "true"
    volumes:
      - open-archiver-data:/var/data/open-archiver
    depends_on:
      - open-archiver-meilisearch

  open-archiver-meilisearch:
    image: getmeili/meilisearch:v1.38
    restart: unless-stopped
    environment:
      MEILI_MASTER_KEY: "$meili_key"
      MEILI_ENV: production
    volumes:
      - open-archiver-meili:/meili_data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - open-archiver-app

volumes:
  open-archiver-data:
  open-archiver-meili:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 2G;
    location / {
        proxy_pass http://open-archiver-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_request_buffering off;
    }
}
NGINX
}
