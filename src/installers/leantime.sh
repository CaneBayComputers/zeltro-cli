INSTALL_DISPLAY="Leantime"
INSTALL_CREDENTIALS="admin@leantime.io / admin"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to complete setup wizard on first launch."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS leantime;"
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  leantime-app:
    image: leantime/leantime:latest
    restart: unless-stopped
    environment:
      LEAN_DB_HOST: zeltro-mariadb
      LEAN_DB_PORT: "3306"
      LEAN_DB_USER: root
      LEAN_DB_PASSWORD: ""
      LEAN_DB_DATABASE: leantime
      LEAN_APP_URL: http://leantime
      LEAN_SESSION_PASSWORD: zeltro-leantime-session
      LEAN_DEFAULT_TIMEZONE: UTC
    volumes:
      - leantime-userfiles:/var/www/html/userfiles
      - leantime-public-userfiles:/var/www/html/public/userfiles
      - leantime-plugins:/var/www/html/app/Plugins
      - leantime-logs:/var/www/html/storage/logs

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - leantime-app

volumes:
  leantime-userfiles:
  leantime-public-userfiles:
  leantime-plugins:
  leantime-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://leantime-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
