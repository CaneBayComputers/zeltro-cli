INSTALL_DISPLAY="Flame"
INSTALL_CREDENTIALS="Password: admin (set in settings)"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  flame-app:
    image: pawelmalak/flame:latest
    restart: unless-stopped
    environment:
      PASSWORD: admin
    volumes:
      - flame-data:/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - flame-app

volumes:
  flame-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://flame-app:5005;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
