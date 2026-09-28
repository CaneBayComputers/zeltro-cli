INSTALL_DISPLAY="Docmost"
INSTALL_CREDENTIALS="Create the workspace owner on first visit"
INSTALL_NOTES="Uses the shared zeltro-postgres and zeltro-redis; no bundled services."
INSTALL_READY_RETRIES=40

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE docmost;" 2>/dev/null || true
}

write_files() {
    local app_secret
    app_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  docmost-app:
    image: docmost/docmost:0.95.0
    restart: unless-stopped
    environment:
      APP_URL: http://docmost
      APP_SECRET: "$app_secret"
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/docmost
      REDIS_URL: redis://zeltro-redis:6379
      MAIL_DRIVER: smtp
      SMTP_HOST: zeltro-mailhog
      SMTP_PORT: 1025
      SMTP_SECURE: "false"
      MAIL_FROM_ADDRESS: docmost@example.com
      MAIL_FROM_NAME: Docmost
    volumes:
      - docmost-data:/app/data/storage

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - docmost-app

volumes:
  docmost-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://docmost-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
