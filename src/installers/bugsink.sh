INSTALL_DISPLAY="Bugsink"
INSTALL_CREDENTIALS="admin@example.com / admin123"
INSTALL_NOTES="Self-hosted Sentry-compatible error tracker. Create a project in the UI to get a DSN pointing at http://bugsink/."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE bugsink;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  bugsink-app:
    image: bugsink/bugsink:2.5.0
    restart: unless-stopped
    environment:
      SECRET_KEY: "$secret_key"
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/bugsink
      BASE_URL: http://bugsink
      PORT: "8000"
      CREATE_SUPERUSER: "admin@example.com:admin123"
      BEHIND_HTTPS_PROXY: "false"
      USE_X_FORWARDED_HOST: "false"
      EMAIL_HOST: zeltro-mailhog
      EMAIL_PORT: "1025"
      EMAIL_USE_TLS: "false"
      DEFAULT_FROM_EMAIL: bugsink@example.com

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - bugsink-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://bugsink-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
    }
}
NGINX
}
