INSTALL_DISPLAY="BookLore"
INSTALL_CREDENTIALS="create the admin account on first visit"
INSTALL_NOTES="Java/Spring app — first boot runs Flyway migrations and can take ~60 seconds before it answers."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS booklore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE USER IF NOT EXISTS 'booklore'@'%' IDENTIFIED BY 'booklore';
        ALTER USER 'booklore'@'%' IDENTIFIED BY 'booklore';
        GRANT ALL PRIVILEGES ON booklore.* TO 'booklore'@'%';
        FLUSH PRIVILEGES;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  booklore-app:
    image: ghcr.io/booklore-app/booklore:v2.3.1
    restart: unless-stopped
    environment:
      USER_ID: "1000"
      GROUP_ID: "1000"
      TZ: Etc/UTC
      DATABASE_URL: jdbc:mariadb://zeltro-mariadb:3306/booklore
      DATABASE_USERNAME: booklore
      DATABASE_PASSWORD: booklore
      SWAGGER_ENABLED: "false"
      FORCE_DISABLE_OIDC: "false"
    volumes:
      - booklore-data:/app/data
      - booklore-books:/books
      - booklore-bookdrop:/bookdrop

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - booklore-app

volumes:
  booklore-data:
  booklore-books:
  booklore-bookdrop:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://booklore-app:6060;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
NGINX
}
