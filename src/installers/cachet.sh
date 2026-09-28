INSTALL_DISPLAY="Cachet"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to complete the setup wizard and create your admin account."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE cachet;" 2>/dev/null || true
}

write_files() {
    local app_key
    app_key="base64:$(openssl rand -base64 32)"

    cat > docker-compose.yaml << EOF
services:
  cachet-app:
    image: cachethq/docker:latest
    restart: unless-stopped
    environment:
      APP_ENV: production
      APP_DEBUG: "false"
      APP_URL: http://cachet
      APP_LOG: errorlog
      APP_KEY: $app_key
      DB_DRIVER: pgsql
      DB_HOST: zeltro-postgres
      DB_PORT: 5432
      DB_DATABASE: cachet
      DB_USERNAME: root
      DB_PASSWORD: password
      DB_PREFIX: chq_
      CACHE_DRIVER: apc
      SESSION_DRIVER: apc
      QUEUE_DRIVER: database
      MAIL_DRIVER: smtp
      MAIL_HOST: zeltro-mailhog
      MAIL_PORT: 1025
      MAIL_ADDRESS: cachet@example.com
      MAIL_NAME: Cachet
      TRUSTED_PROXIES: "*"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - cachet-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 32M;
    location / {
        proxy_pass http://cachet-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
