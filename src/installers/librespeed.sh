INSTALL_DISPLAY="LibreSpeed"
INSTALL_CREDENTIALS="no login required"
INSTALL_NOTES="Results reflect the Docker bridge network, not your real WAN link."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  librespeed-app:
    image: ghcr.io/librespeed/speedtest:6.2.0
    restart: unless-stopped
    environment:
      MODE: standalone
      TITLE: LibreSpeed
      TELEMETRY: "false"
      DISABLE_IPINFO: "true"
      WEBPORT: "8080"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - librespeed-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://librespeed-app:8080;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX
}
