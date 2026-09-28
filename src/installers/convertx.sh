INSTALL_DISPLAY="ConvertX"
INSTALL_CREDENTIALS="register on first visit"
INSTALL_NOTES="HTTP_ALLOWED=true is required — without it login fails over plain http."

write_files() {
    local jwt_secret
    jwt_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  convertx-app:
    image: ghcr.io/c4illin/convertx:v0.18.0
    restart: unless-stopped
    environment:
      JWT_SECRET: "$jwt_secret"
      HTTP_ALLOWED: "true"
      ACCOUNT_REGISTRATION: "false"
      AUTO_DELETE_EVERY_N_HOURS: "24"
    volumes:
      - convertx-data:/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - convertx-app

volumes:
  convertx-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://convertx-app:3000;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 900s;
        proxy_send_timeout 900s;
    }
}
NGINX
}
