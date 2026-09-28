INSTALL_DISPLAY="ArchiveBox"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to access the archiving interface. Create a superuser with: docker exec -it archivebox-app archivebox manage createsuperuser"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  archivebox-app:
    image: archivebox/archivebox:latest
    command: server --quick-init 0.0.0.0:8000
    restart: unless-stopped
    environment:
      ALLOWED_HOSTS: "*"
      MEDIA_MAX_SIZE: 750m
    volumes:
      - archivebox-data:/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - archivebox-app

volumes:
  archivebox-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 750M;
    location / {
        proxy_pass http://archivebox-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }
}
NGINX
}
