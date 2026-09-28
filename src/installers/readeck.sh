INSTALL_DISPLAY="Readeck"
INSTALL_CREDENTIALS="Create the first user on the /onboarding page at first visit"
INSTALL_NOTES="Keep the readeck-data volume — the auto-generated secret key lives in it, and losing it invalidates every session and token."
INSTALL_READY_RETRIES=30

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  readeck-app:
    image: codeberg.org/readeck/readeck:0.23.4
    restart: unless-stopped
    environment:
      READECK_LOG_LEVEL: info
      READECK_ALLOWED_HOSTS: readeck
    volumes:
      - readeck-data:/readeck

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - readeck-app

volumes:
  readeck-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://readeck-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
