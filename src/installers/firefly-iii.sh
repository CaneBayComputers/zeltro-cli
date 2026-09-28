INSTALL_DISPLAY="Firefly III"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to create the admin account on first launch."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS firefly CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

write_files() {
    local app_key
    app_key="base64:$(openssl rand -base64 32)"

    cat > docker-compose.yaml << EOF
services:
  firefly-app:
    image: fireflyiii/core:latest
    restart: unless-stopped
    environment:
      APP_ENV: local
      APP_DEBUG: "false"
      APP_KEY: $app_key
      APP_URL: http://firefly-iii
      TRUSTED_PROXIES: "**"
      DB_CONNECTION: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_DATABASE: firefly
      DB_USERNAME: root
      DB_PASSWORD: ""
      MYSQL_USE_SSL: "false"
      CACHE_DRIVER: file
      SESSION_DRIVER: file
      MAIL_MAILER: log
      STATIC_CRON_TOKEN: zeltro-local-firefly
    volumes:
      - firefly-upload:/var/www/html/storage/upload

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - firefly-app

volumes:
  firefly-upload:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://firefly-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }
}
NGINX
}
