INSTALL_DISPLAY="Kimai"
INSTALL_CREDENTIALS="admin@example.com / admin123"

write_files() {
    local app_secret
    app_secret=$(openssl rand -hex 16)

    cat > docker-compose.yaml << EOF
services:
  kimai-app:
    image: kimai/kimai2:apache
    container_name: kimai-app
    restart: unless-stopped
    environment:
      APP_ENV: prod
      TRUSTED_HOSTS: "__ZELTRO_PROJECT__,__ZELTRO_IP__,localhost,127.0.0.1"
      ADMINMAIL: admin@example.com
      ADMINPASS: admin123
      DATABASE_URL: mysql://root:@zeltro-mariadb:3306/kimai
      APP_SECRET: "$app_secret"
    volumes:
      - kimai-data:/opt/kimai/var/data
      - kimai-plugins:/opt/kimai/var/plugins

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - kimai-app

volumes:
  kimai-data:
  kimai-plugins:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://kimai-app:8001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
