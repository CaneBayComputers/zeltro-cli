INSTALL_DISPLAY="Forgejo"
INSTALL_NOTES="Complete the install wizard on first visit — the DB fields are pre-filled; the first registered user becomes admin."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS forgejo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  forgejo-app:
    image: codeberg.org/forgejo/forgejo:16.0.2
    restart: unless-stopped
    environment:
      USER_UID: 1000
      USER_GID: 1000
      FORGEJO__database__DB_TYPE: mysql
      FORGEJO__database__HOST: zeltro-mariadb:3306
      FORGEJO__database__NAME: forgejo
      FORGEJO__database__USER: root
      FORGEJO__database__PASSWD: ""
      FORGEJO__server__DOMAIN: __ZELTRO_IP__
      FORGEJO__server__ROOT_URL: http://forgejo/
      FORGEJO__server__HTTP_PORT: 3000
      FORGEJO__server__SSH_DOMAIN: __ZELTRO_IP__
      FORGEJO__mailer__ENABLED: "true"
      FORGEJO__mailer__PROTOCOL: smtp
      FORGEJO__mailer__SMTP_ADDR: zeltro-mailhog
      FORGEJO__mailer__SMTP_PORT: 1025
      FORGEJO__mailer__FROM: forgejo@example.com
    volumes:
      - forgejo-data:/data

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - forgejo-app

volumes:
  forgejo-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 512M;
    location / {
        proxy_pass http://forgejo-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
    }
}
NGINX
}
