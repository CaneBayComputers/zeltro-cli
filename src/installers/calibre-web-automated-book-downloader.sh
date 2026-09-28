INSTALL_DISPLAY="Calibre-Web Automated Book Downloader (Shelfmark)"
INSTALL_CREDENTIALS="create the first account on first visit"
INSTALL_NOTES="Upstream renamed the project to Shelfmark; sources and download clients are configured inside the web UI."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  shelfmark-app:
    image: ghcr.io/calibrain/shelfmark:1.3.5
    restart: unless-stopped
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: UTC
    volumes:
      - shelfmark-config:/config
      - shelfmark-books:/books

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - shelfmark-app

volumes:
  shelfmark-config:
  shelfmark-books:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 1G;
    location / {
        proxy_pass http://shelfmark-app:8084;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_buffering off;
    }
}
NGINX
}
