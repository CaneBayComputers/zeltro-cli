INSTALL_DISPLAY="LibreTranslate"
INSTALL_CREDENTIALS="no login required"
INSTALL_NOTES="First boot downloads language models — LT_LOAD_ONLY keeps that to a few hundred MB. Drop it to install every language."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  libretranslate-app:
    image: libretranslate/libretranslate:v1.9.6
    restart: unless-stopped
    environment:
      LT_LOAD_ONLY: "en,es,fr,de"
      LT_HOST: 0.0.0.0
      LT_PORT: "5000"
      LT_DISABLE_WEB_UI: "false"
    volumes:
      - libretranslate-models:/home/libretranslate/.local

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - libretranslate-app

volumes:
  libretranslate-models:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://libretranslate-app:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
}
NGINX
}
