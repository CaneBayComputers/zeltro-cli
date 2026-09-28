INSTALL_DISPLAY="Unleash"
INSTALL_CREDENTIALS="admin / unleash4all"
INSTALL_NOTES="Change the default admin password after the first login."

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"unleash\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  unleash-app:
    image: unleashorg/unleash-server:8.1.0
    restart: unless-stopped
    environment:
      DATABASE_URL: "postgres://root:password@zeltro-postgres:5432/unleash"
      DATABASE_SSL: "false"
      UNLEASH_URL: http://unleash
      LOG_LEVEL: warn
      INIT_FRONTEND_API_TOKENS: "default:development.unleash-insecure-frontend-api-token"
      INIT_BACKEND_API_TOKENS: "default:development.unleash-insecure-api-token"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - unleash-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://unleash-app:4242;
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
