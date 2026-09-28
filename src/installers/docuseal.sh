INSTALL_DISPLAY="DocuSeal"
INSTALL_CREDENTIALS="Create the admin account on first visit"
INSTALL_NOTES="Do not set FORCE_SSL — Zeltro serves the app over plain http."
INSTALL_READY_RETRIES=40

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE docuseal;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  docuseal-app:
    image: docuseal/docuseal:3.1.7
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/docuseal
    volumes:
      - docuseal-data:/data/docuseal

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - docuseal-app

volumes:
  docuseal-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://docuseal-app:3000;
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
