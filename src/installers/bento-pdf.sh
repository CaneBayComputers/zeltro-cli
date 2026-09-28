INSTALL_DISPLAY="BentoPDF"
INSTALL_CREDENTIALS="No login — open the site and start using the tools"
INSTALL_NOTES="Fully client-side: PDFs never leave the browser. Some tools fetch WASM modules from a CDN on first use, so they need internet access."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  bento-pdf-app:
    image: ghcr.io/alam00000/bentopdf-simple:v2.8.7
    restart: unless-stopped

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - bento-pdf-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 512M;
    location / {
        proxy_pass http://bento-pdf-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
