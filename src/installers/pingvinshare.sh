INSTALL_DISPLAY="Pingvin Share"
INSTALL_CREDENTIALS="register on first visit — the first account becomes admin"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  pingvinshare-app:
    image: ghcr.io/stonith404/pingvin-share:v1.13.0
    restart: unless-stopped
    environment:
      TRUST_PROXY: "true"
    volumes:
      - pingvinshare-data:/opt/app/backend/data
      - pingvinshare-images:/opt/app/frontend/public/img

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - pingvinshare-app

volumes:
  pingvinshare-data:
  pingvinshare-images:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://pingvinshare-app:3000;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 900s;
        proxy_send_timeout 900s;
    }
}
NGINX
}
