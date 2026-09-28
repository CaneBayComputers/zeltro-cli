INSTALL_DISPLAY="PocketBase"
INSTALL_CREDENTIALS="admin@example.com / admin1234567890 (admin UI at http://pocketbase/_/)"
INSTALL_NOTES="No official image exists; this uses the de-facto community build. / redirects to the admin UI because no pb_public is bundled."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  pocketbase-app:
    image: ghcr.io/muchobien/pocketbase:0.39.10
    restart: unless-stopped
    environment:
      PB_HOST: 0.0.0.0
      PB_PORT: 8090
      PB_ADMIN_EMAIL: admin@example.com
      PB_ADMIN_PASSWORD: admin1234567890
    volumes:
      - pocketbase-data:/pb_data
      - pocketbase-public:/pb_public

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - pocketbase-app

volumes:
  pocketbase-data:
  pocketbase-public:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;

    # PocketBase serves nothing at / until you add files to pb_public,
    # so send the bare root at the admin dashboard instead of a 404.
    location = / {
        return 302 /_/;
    }

    location / {
        proxy_pass http://pocketbase-app:8090;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
