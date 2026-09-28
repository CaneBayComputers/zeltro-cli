INSTALL_DISPLAY="Memos"
INSTALL_NOTES="First user to register becomes admin."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  memos-app:
    image: neosmemo/memos:stable
    restart: unless-stopped
    volumes:
      - memos-data:/var/opt/memos

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - memos-app

volumes:
  memos-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://memos-app:5230;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
