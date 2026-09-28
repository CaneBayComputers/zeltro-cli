INSTALL_DISPLAY="Outline"
INSTALL_NOTES="Outline requires an auth provider. Configure OIDC or email auth via env vars before first use."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE outline;" 2>/dev/null || true
}

write_files() {
    local secret_key utils_secret
    secret_key=$(openssl rand -hex 32)
    utils_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  outline-app:
    image: outlinewiki/outline:latest
    restart: unless-stopped
    environment:
      APP_NAME: outline
      APP_ENV: production
      URL: http://outline
      PORT: 3000
      FORCE_HTTPS: "false"
      SECRET_KEY: "$secret_key"
      UTILS_SECRET: "$utils_secret"
      DATABASE_URL: postgres://root:password@zeltro-postgres:5432/outline
      PGSSLMODE: disable
      REDIS_URL: redis://zeltro-redis:6379
      FILE_STORAGE: local
      STORAGE_LOCAL_PATH: /var/lib/outline/data
    volumes:
      - outline-data:/var/lib/outline/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - outline-app

volumes:
  outline-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://outline-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
