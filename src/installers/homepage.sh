INSTALL_DISPLAY="Homepage"
INSTALL_NOTES="Config YAML lives in the homepage-config volume (/app/config); defaults are generated on first boot."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  homepage-app:
    image: ghcr.io/gethomepage/homepage:v1.13.2
    restart: unless-stopped
    environment:
      HOMEPAGE_ALLOWED_HOSTS: "*"
      PORT: "3000"
      LOG_LEVEL: info
    volumes:
      - homepage-config:/app/config
      - homepage-images:/app/public/images

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - homepage-app

volumes:
  homepage-config:
  homepage-images:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://homepage-app:3000;
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
