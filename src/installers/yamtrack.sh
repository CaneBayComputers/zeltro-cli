INSTALL_DISPLAY="Yamtrack"
INSTALL_CREDENTIALS="register on first visit"
INSTALL_NOTES="Add a TMDB API key under Settings to enable movie/TV metadata lookups."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE yamtrack;" 2>/dev/null || true
}

write_files() {
    local secret
    secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  yamtrack-app:
    image: ghcr.io/fuzzygrim/yamtrack:0.25.3
    restart: unless-stopped
    environment:
      SECRET: "$secret"
      URLS: http://yamtrack
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      DB_NAME: yamtrack
      DB_USER: root
      DB_PASSWORD: password
      REDIS_URL: redis://zeltro-redis:6379/2
      REDIS_PREFIX: yamtrack
      TZ: UTC

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - yamtrack-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://yamtrack-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
