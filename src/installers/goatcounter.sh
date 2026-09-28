INSTALL_DISPLAY="GoatCounter"
INSTALL_CREDENTIALS="Create your first site and user on first visit"
INSTALL_NOTES="On the setup form leave the site domain BLANK — a bare hostname like 'goatcounter' fails GoatCounter's two-label domain validation."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  goatcounter-app:
    image: arp242/goatcounter:2.7.0
    restart: unless-stopped
    command: ["serve", "-automigrate", "-listen", ":8080", "-tls", "http"]
    volumes:
      - goatcounter-data:/home/goatcounter/goatcounter-data

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - goatcounter-app

volumes:
  goatcounter-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://goatcounter-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
