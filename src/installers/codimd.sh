INSTALL_DISPLAY="CodiMD"
INSTALL_CREDENTIALS="Register on first visit (anonymous notes are enabled too)"
INSTALL_NOTES="CodiMD has no admin account or admin UI — every user self-registers."
INSTALL_READY_RETRIES=30

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE codimd;" 2>/dev/null || true
}

write_files() {
    local session_secret
    session_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  codimd-app:
    image: hackmdio/hackmd:2.6.1
    restart: unless-stopped
    environment:
      CMD_DB_URL: postgres://root:password@zeltro-postgres:5432/codimd
      CMD_DOMAIN: __ZELTRO_IP__
      CMD_URL_ADDPORT: "false"
      CMD_PROTOCOL_USESSL: "false"
      CMD_HSTS_ENABLE: "false"
      CMD_USECDN: "false"
      CMD_ALLOW_ANONYMOUS: "true"
      CMD_ALLOW_FREEURL: "true"
      CMD_SESSION_SECRET: "$session_secret"
      CMD_IMAGE_UPLOAD_TYPE: filesystem
    volumes:
      - codimd-uploads:/home/hackmd/app/public/uploads

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - codimd-app

volumes:
  codimd-uploads:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://codimd-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
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
