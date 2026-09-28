INSTALL_DISPLAY="Zipline"
INSTALL_CREDENTIALS="administrator / password"
INSTALL_NOTES="Change the administrator password immediately after the first login."

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"zipline\";" 2>/dev/null || true
}

write_files() {
    local core_secret
    core_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  zipline-app:
    image: ghcr.io/diced/zipline:4.6.5
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://root:password@zeltro-postgres:5432/zipline
      CORE_SECRET: "$core_secret"
      CORE_HOSTNAME: 0.0.0.0
      CORE_PORT: "3000"
      DATASOURCE_TYPE: local
      DATASOURCE_LOCAL_DIRECTORY: /zipline/uploads
    volumes:
      - zipline-uploads:/zipline/uploads
      - zipline-public:/zipline/public
      - zipline-themes:/zipline/themes

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - zipline-app

volumes:
  zipline-uploads:
  zipline-public:
  zipline-themes:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://zipline-app:3000;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 900s;
        proxy_send_timeout 900s;
    }
}
NGINX
}
