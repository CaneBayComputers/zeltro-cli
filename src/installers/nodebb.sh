INSTALL_DISPLAY="NodeBB"
INSTALL_CREDENTIALS="admin / admin123456"
INSTALL_NOTES="First boot installs and then exits once — the restart policy brings it back up serving the forum. Give it a couple of minutes."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"nodebb\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  nodebb-app:
    image: ghcr.io/nodebb/nodebb:4.9.0
    restart: unless-stopped
    environment:
      NODEBB_URL: http://nodebb
      NODEBB_DB: postgres
      NODEBB_DB_HOST: zeltro-postgres
      NODEBB_DB_PORT: 5432
      NODEBB_DB_NAME: nodebb
      NODEBB_DB_USER: root
      NODEBB_DB_PASSWORD: password
      NODEBB_DB_SSL: "false"
      NODEBB_ADMIN_USERNAME: admin
      NODEBB_ADMIN_PASSWORD: admin123456
      NODEBB_ADMIN_EMAIL: admin@example.com
    volumes:
      - nodebb-config:/opt/config
      - nodebb-build:/usr/src/app/build
      - nodebb-uploads:/usr/src/app/public/uploads

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - nodebb-app

volumes:
  nodebb-config:
  nodebb-build:
  nodebb-uploads:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://nodebb-app:4567;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
