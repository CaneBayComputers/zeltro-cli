INSTALL_DISPLAY="Infisical"
INSTALL_CREDENTIALS="register on first visit — the first account becomes the instance admin"
INSTALL_NOTES="The container runs its database migrations on boot; the UI 502s for a few seconds until they finish."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"infisical\";" 2>/dev/null || true
}

write_files() {
    local encryption_key auth_secret
    encryption_key=$(openssl rand -hex 16)
    auth_secret=$(openssl rand -base64 32)

    cat > docker-compose.yaml << EOF
services:
  infisical-app:
    image: infisical/infisical:v0.162.16
    restart: unless-stopped
    environment:
      NODE_ENV: production
      ENCRYPTION_KEY: "$encryption_key"
      AUTH_SECRET: "$auth_secret"
      DB_CONNECTION_URI: "postgres://root:password@zeltro-postgres:5432/infisical"
      REDIS_URL: "redis://zeltro-redis:6379/3"
      SITE_URL: "http://infisical"
      SMTP_HOST: zeltro-mailhog
      SMTP_PORT: 1025
      SMTP_FROM_ADDRESS: infisical@example.com
      SMTP_FROM_NAME: Infisical
      SMTP_SECURE: "false"
      TELEMETRY_ENABLED: "false"

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - infisical-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://infisical-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
