INSTALL_DISPLAY="Dashy"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  dashy-app:
    image: lissy93/dashy:latest
    restart: unless-stopped
    environment:
      NODE_ENV: production
    volumes:
      - dashy-data:/app/user-data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - dashy-app

volumes:
  dashy-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://dashy-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
