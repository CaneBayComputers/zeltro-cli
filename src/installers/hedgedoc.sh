INSTALL_DISPLAY="HedgeDoc"
INSTALL_NOTES="Register an account on first visit. Anonymous access is enabled by default."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE hedgedoc;" 2>/dev/null || true
}

write_files() {
    local session_secret
    session_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  hedgedoc-app:
    image: quay.io/hedgedoc/hedgedoc:latest
    restart: unless-stopped
    environment:
      CMD_DB_URL: postgres://root:password@zeltro-postgres:5432/hedgedoc
      CMD_DOMAIN: __ZELTRO_IP__
      CMD_URL_ADDPORT: "false"
      CMD_PROTOCOL_USESSL: "false"
      CMD_SESSION_SECRET: "$session_secret"
      CMD_ALLOW_ANONYMOUS: "true"
      CMD_ALLOW_FREEURL: "true"
    volumes:
      - hedgedoc-uploads:/hedgedoc/public/uploads

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - hedgedoc-app

volumes:
  hedgedoc-uploads:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://hedgedoc-app:3000;
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
