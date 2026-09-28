INSTALL_DISPLAY="Miniflux"
INSTALL_CREDENTIALS="admin / admin123"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE miniflux;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  miniflux-app:
    image: miniflux/miniflux:latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://root:password@zeltro-postgres:5432/miniflux?sslmode=disable
      RUN_MIGRATIONS: "1"
      CREATE_ADMIN: "1"
      ADMIN_USERNAME: admin
      ADMIN_PASSWORD: admin123
      BASE_URL: http://miniflux/

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - miniflux-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://miniflux-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
