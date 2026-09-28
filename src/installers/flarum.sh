INSTALL_DISPLAY="Flarum"
INSTALL_CREDENTIALS="admin / AdminPassword123!"
INSTALL_NOTES="First startup takes a few minutes while Flarum installs. Visit http://$PROJECT_NAME/ once it's ready."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS flarum CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    # Flarum requires its own dedicated user — root login fails with this image
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE USER IF NOT EXISTS 'flarum'@'%' IDENTIFIED BY 'FlarumDbPassword123!';
        ALTER USER 'flarum'@'%' IDENTIFIED BY 'FlarumDbPassword123!';
        GRANT ALL PRIVILEGES ON flarum.* TO 'flarum'@'%';
        FLUSH PRIVILEGES;
    "
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  flarum-app:
    image: mondedie/flarum:latest
    restart: unless-stopped
    environment:
      FORUM_URL: http://flarum
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_NAME: flarum
      DB_USER: flarum
      DB_PASS: "FlarumDbPassword123!"
      FLARUM_PORT: 8888
      FLARUM_TITLE: Flarum
      FLARUM_ADMIN_USER: admin
      FLARUM_ADMIN_PASS: AdminPassword123!
      FLARUM_ADMIN_MAIL: admin@flarum.local
      LOG_TO_STDOUT: "true"
      UPLOAD_MAX_SIZE: 50M
    volumes:
      - flarum-assets:/flarum/app/public/assets
      - flarum-extensions:/flarum/app/extensions
      - flarum-logs:/flarum/app/storage/logs

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - flarum-app

volumes:
  flarum-assets:
  flarum-extensions:
  flarum-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://flarum-app:8888;
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
