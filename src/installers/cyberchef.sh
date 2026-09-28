INSTALL_DISPLAY="CyberChef"
INSTALL_CREDENTIALS="no login required"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  cyberchef-app:
    image: mpepping/cyberchef:v11.2.0
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - cyberchef-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://cyberchef-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
