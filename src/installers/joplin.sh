INSTALL_DISPLAY="Joplin Server"
INSTALL_CREDENTIALS="admin@localhost / admin"
INSTALL_NOTES="Change the default admin password immediately; sync clients point at http://joplin/."
INSTALL_READY_RETRIES=40

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE joplin;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  joplin-app:
    image: joplin/server:3.7.1
    restart: unless-stopped
    environment:
      APP_PORT: 22300
      APP_BASE_URL: http://joplin
      DB_CLIENT: pg
      POSTGRES_HOST: zeltro-postgres
      POSTGRES_PORT: 5432
      POSTGRES_DATABASE: joplin
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      MAILER_ENABLED: 1
      MAILER_HOST: zeltro-mailhog
      MAILER_PORT: 1025
      MAILER_SECURITY: none
      MAILER_NOREPLY_EMAIL: joplin@example.com

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - joplin-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://joplin-app:22300;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
