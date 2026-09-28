INSTALL_DISPLAY="Twenty CRM"
INSTALL_CREDENTIALS="Register on first visit"
INSTALL_NOTES="First boot runs database migrations and can take 2-3 minutes before the UI answers."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE twenty;" 2>/dev/null || true
}

write_files() {
    local encryption_key app_secret
    encryption_key=$(openssl rand -base64 32 | tr -d '\n')
    app_secret=$(openssl rand -base64 32 | tr -d '\n')

    cat > docker-compose.yaml << EOF
services:
  twenty-server:
    image: twentycrm/twenty:v2.27.0
    restart: unless-stopped
    environment:
      NODE_PORT: "3000"
      SERVER_URL: http://twenty
      PG_DATABASE_URL: postgres://root:password@zeltro-postgres:5432/twenty
      REDIS_URL: redis://zeltro-redis:6379
      STORAGE_TYPE: local
      ENCRYPTION_KEY: "$encryption_key"
      APP_SECRET: "$app_secret"
      DISABLE_DB_MIGRATIONS: "false"
      DISABLE_CRON_JOBS_REGISTRATION: "false"
    volumes:
      - twenty-server-local-data:/app/packages/twenty-server/.local-storage
    healthcheck:
      test: ["CMD-SHELL", "curl --fail http://localhost:3000/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 120s

  twenty-worker:
    image: twentycrm/twenty:v2.27.0
    restart: unless-stopped
    command: ["yarn", "worker:prod"]
    environment:
      SERVER_URL: http://twenty
      PG_DATABASE_URL: postgres://root:password@zeltro-postgres:5432/twenty
      REDIS_URL: redis://zeltro-redis:6379
      STORAGE_TYPE: local
      ENCRYPTION_KEY: "$encryption_key"
      APP_SECRET: "$app_secret"
      DISABLE_DB_MIGRATIONS: "true"
      DISABLE_CRON_JOBS_REGISTRATION: "true"
    volumes:
      - twenty-server-local-data:/app/packages/twenty-server/.local-storage
    depends_on:
      twenty-server:
        condition: service_healthy

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - twenty-server

volumes:
  twenty-server-local-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://twenty-server:3000;
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
