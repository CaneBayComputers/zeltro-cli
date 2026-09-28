INSTALL_DISPLAY="linkding"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="SQLite-backed; the superuser is created from LD_SUPERUSER_* on first boot only."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  linkding-app:
    image: sissbruecker/linkding:1.45.0
    restart: unless-stopped
    environment:
      LD_SUPERUSER_NAME: admin
      LD_SUPERUSER_PASSWORD: admin123
      LD_CSRF_TRUSTED_ORIGINS: http://linkding
      LD_DISABLE_BACKGROUND_TASKS: "False"
    volumes:
      - linkding-data:/etc/linkding/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - linkding-app

volumes:
  linkding-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://linkding-app:9090;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
