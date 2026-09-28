INSTALL_DISPLAY="Wiki.js"
INSTALL_NOTES="Complete the setup wizard on first visit to create the admin account."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE wikijs;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  wikijs-app:
    image: ghcr.io/requarks/wiki:2
    restart: unless-stopped
    environment:
      DB_TYPE: postgres
      DB_HOST: zeltro-postgres
      DB_PORT: 5432
      DB_USER: root
      DB_PASS: password
      DB_NAME: wikijs

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - wikijs-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://wikijs-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
