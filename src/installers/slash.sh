INSTALL_DISPLAY="Slash"
INSTALL_CREDENTIALS="register on first visit (first account becomes the host/admin)"
INSTALL_NOTES="Bookmark and link-shortener platform. Data lives in SQLite inside the slash-data volume."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  slash-app:
    image: yourselfhosted/slash:0.5.3
    restart: unless-stopped
    environment:
      SLASH_MODE: prod
      SLASH_PORT: "5231"
    volumes:
      - slash-data:/var/opt/slash

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - slash-app

volumes:
  slash-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 32M;
    location / {
        proxy_pass http://slash-app:5231;
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
