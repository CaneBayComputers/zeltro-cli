INSTALL_DISPLAY="SearXNG"
INSTALL_NOTES="No login required — it's a public metasearch engine."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  searxng-app:
    image: searxng/searxng:latest
    restart: unless-stopped
    environment:
      SEARXNG_BASE_URL: http://searxng/

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - searxng-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://searxng-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
