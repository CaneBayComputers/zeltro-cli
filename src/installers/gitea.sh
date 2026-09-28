INSTALL_DISPLAY="Gitea"
INSTALL_NOTES="Register the first user through the web UI — that account becomes admin."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS gitea;"
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  gitea-app:
    image: gitea/gitea:latest
    restart: unless-stopped
    environment:
      USER_UID: 1000
      USER_GID: 1000
      GITEA__database__DB_TYPE: mysql
      GITEA__database__HOST: zeltro-mariadb:3306
      GITEA__database__NAME: gitea
      GITEA__database__USER: root
      GITEA__database__PASSWD: ""
      GITEA__server__ROOT_URL: http://gitea/
      GITEA__server__DOMAIN: __ZELTRO_IP__
      GITEA__server__HTTP_PORT: 3000
    volumes:
      - gitea-data:/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - gitea-app

volumes:
  gitea-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://gitea-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
