INSTALL_DISPLAY="New API"
INSTALL_CREDENTIALS="root / 123456 (change it immediately after first login)"
INSTALL_NOTES="OpenAI-compatible relay/gateway with token quotas. The default root password is fixed by upstream."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS newapi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE USER IF NOT EXISTS 'newapi'@'%' IDENTIFIED BY 'newapi';
        ALTER USER 'newapi'@'%' IDENTIFIED BY 'newapi';
        GRANT ALL PRIVILEGES ON newapi.* TO 'newapi'@'%';
        FLUSH PRIVILEGES;" 2>/dev/null || true
}

write_files() {
    local session_secret
    session_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  newapi-app:
    image: calciumion/new-api:v1.0.0-rc.23
    restart: unless-stopped
    command: --log-dir /app/logs
    environment:
      SQL_DSN: newapi:newapi@tcp(zeltro-mariadb:3306)/newapi
      REDIS_CONN_STRING: redis://zeltro-redis:6379/4
      SESSION_SECRET: "$session_secret"
      TZ: UTC
      ERROR_LOG_ENABLED: "true"
      BATCH_UPDATE_ENABLED: "true"
      NODE_NAME: newapi-zeltro
    volumes:
      - newapi-data:/data
      - newapi-logs:/app/logs

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - newapi-app

volumes:
  newapi-data:
  newapi-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 128M;
    location / {
        proxy_pass http://newapi-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
