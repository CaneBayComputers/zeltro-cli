INSTALL_DISPLAY="Standard Notes"
INSTALL_NOTES="Self-hosted encrypted notes server. Connect with the Standard Notes app at http://$PROJECT_NAME/. Use the Standard Notes desktop/mobile app to register and sync."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS standard_notes CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE USER IF NOT EXISTS 'standard_notes'@'%' IDENTIFIED BY 'SnDbPass123!';
        ALTER USER 'standard_notes'@'%' IDENTIFIED BY 'SnDbPass123!';
        GRANT ALL PRIVILEGES ON standard_notes.* TO 'standard_notes'@'%';
        FLUSH PRIVILEGES;
    "
}

write_files() {
    local auth_secret server_secret valet_secret enc_server_key pseudo_key
    auth_secret=$(openssl rand -hex 32)
    server_secret=$(openssl rand -hex 32)
    valet_secret=$(openssl rand -hex 32)
    enc_server_key=$(openssl rand -hex 32)
    pseudo_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  standard-notes-app:
    image: standardnotes/server:latest
    restart: unless-stopped
    environment:
      EXPOSED_PORT: "3000"
      PUBLIC_URL: http://standard-notes
      DB_TYPE: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: "3306"
      DB_USERNAME: standard_notes
      DB_PASSWORD: "SnDbPass123!"
      DB_DATABASE: standard_notes
      DB_MIGRATIONS_PATH: dist/migrations/*.js
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      REDIS_URL: redis://zeltro-redis:6379
      CACHE_TYPE: redis
      AUTH_JWT_SECRET: $auth_secret
      AUTH_SERVER_ENCRYPTION_SERVER_KEY: $enc_server_key
      VALET_TOKEN_SECRET: $valet_secret
      AUTH_PSEUDO_KEY_PARAMS_KEY: $pseudo_key
      NODE_ENV: production
      LOG_LEVEL: info
    volumes:
      - standard-notes-uploads:/opt/server/packages/files/dist/uploads

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - standard-notes-app

volumes:
  standard-notes-uploads:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://standard-notes-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
    }
}
NGINX
}
