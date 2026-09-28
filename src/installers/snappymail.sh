INSTALL_DISPLAY="Snappymail"
INSTALL_NOTES="Admin panel at http://$PROJECT_NAME/?admin — set the admin password on first visit. Configure IMAP/SMTP servers in the admin panel."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  snappymail-app:
    image: djmaze/snappymail:latest
    restart: unless-stopped
    environment:
      SNAPPYMAIL_INCLUDE_ADMINPANEL: "True"
    volumes:
      - snappymail-data:/var/lib/snappymail

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - snappymail-app

volumes:
  snappymail-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 25M;
    location / {
        proxy_pass http://snappymail-app:8888;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
