INSTALL_DISPLAY="Web-Check"
INSTALL_CREDENTIALS="No login — enter a URL and run the checks"
INSTALL_NOTES="Stateless OSINT scanner. Needs outbound internet to inspect target sites; some checks stay disabled until you add third-party API keys."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  checker:
    image: lissy93/web-check:2.2.2
    restart: unless-stopped

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - checker
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://checker:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
    }
}
NGINX
}
