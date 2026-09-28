INSTALL_DISPLAY="Nginx Proxy Manager"
INSTALL_CREDENTIALS="admin@example.com / changeme"
INSTALL_NOTES="Change the default password immediately after first login."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  npm-app:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    volumes:
      - npm-data:/data
      - npm-letsencrypt:/etc/letsencrypt

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - npm-app

volumes:
  npm-data:
  npm-letsencrypt:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://npm-app:81;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
