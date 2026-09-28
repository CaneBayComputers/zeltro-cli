INSTALL_DISPLAY="Shlink"
INSTALL_NOTES="Shlink is a URL shortener API. Access the REST API at http://$PROJECT_NAME/rest/v3/. The API key is printed below. Use Shlink Web Client or the shlink CLI to manage links."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS shlink CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

write_files() {
    local api_key
    api_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  shlink-app:
    image: shlinkio/shlink:stable
    restart: unless-stopped
    environment:
      DEFAULT_DOMAIN: __ZELTRO_IP__
      IS_HTTPS_ENABLED: "false"
      SKIP_INITIAL_GEOLITE_DOWNLOAD: "true"
      INITIAL_API_KEY: $api_key
      DEFAULT_BASE_URL_REDIRECT: http://shlink/rest/v3/health
      DB_DRIVER: maria
      DB_NAME: shlink
      DB_USER: root
      DB_PASSWORD: ""
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      REDIS_SERVERS: zeltro-redis:6379
      TRUSTED_PROXIES: 1
      TIMEZONE: UTC

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - shlink-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 16M;
    location / {
        proxy_pass http://shlink-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

    echo ""
    echo "Shlink API key: $api_key"
}
