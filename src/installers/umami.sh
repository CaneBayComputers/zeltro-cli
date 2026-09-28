INSTALL_DISPLAY="Umami"
INSTALL_CREDENTIALS="admin / umami"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE umami;" 2>/dev/null || true
}

write_files() {
    local app_secret
    app_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  umami-app:
    image: ghcr.io/umami-software/umami:postgresql-latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/umami
      APP_SECRET: "$app_secret"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - umami-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://umami-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
