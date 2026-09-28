INSTALL_DISPLAY="Statusnook"
INSTALL_CREDENTIALS="Set the admin account on first visit at http://statusnook/admin"
INSTALL_NOTES="Upstream has not shipped a release since v0.3.0 (2024) and publishes no version tags, so the image is pinned by digest."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  statusnook-app:
    image: goksan/statusnook@sha256:9b2c87213312b1856d52d576d7512aeae71190437b502739f352feba0bcc12e0
    restart: unless-stopped
    environment:
      PORT: "8000"
    volumes:
      - statusnook-data:/app/statusnook-data

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - statusnook-app

volumes:
  statusnook-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 16M;
    location / {
        proxy_pass http://statusnook-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
