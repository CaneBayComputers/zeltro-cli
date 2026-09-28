INSTALL_DISPLAY="Homebox"
INSTALL_CREDENTIALS="Register on first visit"
INSTALL_NOTES="Home inventory manager. Data lives in SQLite under /data — no external database needed."

write_files() {
    local pepper
    pepper=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  homebox-app:
    image: ghcr.io/sysadminsmedia/homebox:0.21.0
    restart: unless-stopped
    environment:
      HBOX_LOG_LEVEL: info
      HBOX_LOG_FORMAT: text
      HBOX_WEB_MAX_UPLOAD_SIZE: "50"
      HBOX_OPTIONS_ALLOW_ANALYTICS: "false"
      HBOX_AUTH_API_KEY_PEPPER: "$pepper"
    volumes:
      - homebox-data:/data

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - homebox-app

volumes:
  homebox-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://homebox-app:7745;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
