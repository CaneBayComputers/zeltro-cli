INSTALL_DISPLAY="marimo"
INSTALL_CREDENTIALS="No login — token auth is disabled in the official image"
INSTALL_NOTES="Save notebooks under the data/ folder — it is the only directory on a volume."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  marimo-app:
    image: ghcr.io/marimo-team/marimo:0.23.15-data
    restart: unless-stopped
    # Default CMD is: marimo edit --no-token -p $PORT --host $HOST
    environment:
      PORT: "8080"
      HOST: 0.0.0.0
      MARIMO_SKIP_UPDATE_CHECK: "1"
    volumes:
      - marimo-notebooks:/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - marimo-app

volumes:
  marimo-notebooks:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://marimo-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_buffering off;
    }
}
NGINX
}
