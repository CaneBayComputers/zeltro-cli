INSTALL_DISPLAY="Kavita"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to create the admin account on first launch."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  kavita-app:
    image: jvmilazz0/kavita:latest
    restart: unless-stopped
    volumes:
      - kavita-config:/kavita/config
      - kavita-books:/books

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - kavita-app

volumes:
  kavita-config:
  kavita-books:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 512M;
    location / {
        proxy_pass http://kavita-app:5000;
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
