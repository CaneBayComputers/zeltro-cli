INSTALL_DISPLAY="Coolify"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to create your admin account. Requires Docker socket access to manage deployments."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE coolify;" 2>/dev/null || true
}

write_files() {
    local app_id app_key pusher_id pusher_key pusher_secret
    app_id=$(openssl rand -hex 16)
    app_key=$(openssl rand -base64 32)
    pusher_id=$(openssl rand -hex 16)
    pusher_key=$(openssl rand -hex 16)
    pusher_secret=$(openssl rand -hex 16)

    cat > docker-compose.yaml << EOF
services:
  coolify-app:
    image: ghcr.io/coollabsio/coolify:latest
    restart: unless-stopped
    environment:
      APP_ID: $app_id
      APP_NAME: Coolify
      APP_KEY: "base64:$app_key"
      APP_URL: http://coolify
      DB_CONNECTION: pgsql
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      DB_DATABASE: coolify
      DB_USERNAME: root
      DB_PASSWORD: password
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      PUSHER_APP_ID: $pusher_id
      PUSHER_APP_KEY: $pusher_key
      PUSHER_APP_SECRET: $pusher_secret
      SSL_MODE: "off"
      AUTOUPDATE: "false"
      SELF_HOSTED: "true"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - coolify-data:/data
      - coolify-ssh:/var/www/html/storage/app/ssh

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - coolify-app

volumes:
  coolify-data:
  coolify-ssh:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://coolify-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINX
}
