INSTALL_DISPLAY="Redmine"
INSTALL_CREDENTIALS="admin / admin (forced to change on first login)"

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS redmine CHARACTER SET utf8mb4;"
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  redmine-app:
    image: redmine:latest
    restart: unless-stopped
    environment:
      REDMINE_DB_MYSQL: zeltro-mariadb
      REDMINE_DB_PORT: 3306
      REDMINE_DB_USERNAME: root
      REDMINE_DB_PASSWORD: ""
      REDMINE_DB_DATABASE: redmine
      REDMINE_SECRET_KEY_BASE: "$secret_key"
    volumes:
      - redmine-files:/usr/src/redmine/files
      - redmine-plugins:/usr/src/redmine/plugins

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - redmine-app

volumes:
  redmine-files:
  redmine-plugins:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://redmine-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
