INSTALL_DISPLAY="Stirling PDF"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  stirling-pdf-app:
    image: frooodle/s-pdf:latest
    restart: unless-stopped
    environment:
      DOCKER_ENABLE_SECURITY: "false"
      SECURITY_ENABLE_LOGIN: "false"
    volumes:
      - stirling-training:/usr/share/tesseract-ocr/5/tessdata

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - stirling-pdf-app

volumes:
  stirling-training:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://stirling-pdf-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
}
NGINX
}
