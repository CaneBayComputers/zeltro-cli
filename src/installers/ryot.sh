INSTALL_DISPLAY="Ryot"
INSTALL_CREDENTIALS="Register on first visit (first user becomes admin)"
INSTALL_NOTES="Roll Your Own Tracker — media, fitness and reading tracker. Metadata providers (TMDB, IGDB, etc.) need internet access."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE ryot;" 2>/dev/null || true
}

write_files() {
    local admin_token
    admin_token=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  ryot-app:
    image: ignisda/ryot:v10.4.2
    restart: unless-stopped
    environment:
      TZ: Etc/UTC
      DATABASE_URL: postgres://root:password@zeltro-postgres:5432/ryot
      FRONTEND_URL: http://ryot
      SERVER_ADMIN_ACCESS_TOKEN: "$admin_token"

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - ryot-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://ryot-app:8000;
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
