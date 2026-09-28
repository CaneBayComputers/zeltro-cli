INSTALL_DISPLAY="Calibre-Web"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="Copy an existing Calibre library (its metadata.db) into the calibre-web-books volume, then point the first-run wizard at /books."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  calibre-web-app:
    image: linuxserver/calibre-web:0.6.26-ls393
    restart: unless-stopped
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: Etc/UTC
    volumes:
      - calibre-web-config:/config
      - calibre-web-books:/books

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - calibre-web-app

volumes:
  calibre-web-config:
  calibre-web-books:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://calibre-web-app:8083;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
NGINX
}
