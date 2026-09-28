INSTALL_DISPLAY="Redash"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to create the admin account on first launch. First startup runs DB migrations — allow ~30 seconds."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE redash;" 2>/dev/null || true
}

write_files() {
    local secret_key cookie_secret
    secret_key=$(openssl rand -hex 32)
    cookie_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  redash-server:
    image: redash/redash:latest
    command: server
    restart: unless-stopped
    environment:
      REDASH_DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/redash
      REDASH_REDIS_URL: redis://zeltro-redis:6379/3
      REDASH_SECRET_KEY: $secret_key
      REDASH_COOKIE_SECRET: $cookie_secret
      REDASH_WEB_WORKERS: 4
      REDASH_MAIL_SERVER: zeltro-mailhog
      REDASH_MAIL_PORT: 1025
      REDASH_MAIL_USE_TLS: "false"
      REDASH_MAIL_USE_SSL: "false"
      REDASH_MAIL_DEFAULT_SENDER: redash@localhost
    depends_on:
      - redash-worker
      - redash-scheduler

  redash-worker:
    image: redash/redash:latest
    command: worker
    restart: unless-stopped
    environment:
      REDASH_DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/redash
      REDASH_REDIS_URL: redis://zeltro-redis:6379/3
      REDASH_SECRET_KEY: $secret_key
      WORKERS_COUNT: 2
      QUEUES: queries,scheduled_queries,celery

  redash-scheduler:
    image: redash/redash:latest
    command: scheduler
    restart: unless-stopped
    environment:
      REDASH_DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/redash
      REDASH_REDIS_URL: redis://zeltro-redis:6379/3
      REDASH_SECRET_KEY: $secret_key

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - redash-server
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://redash-server:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
    }
}
NGINX
}
