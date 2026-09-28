INSTALL_DISPLAY="Linkwarden"
INSTALL_NOTES="Register your account on first visit."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE linkwarden;" 2>/dev/null || true
}

write_files() {
    local nextauth_secret
    nextauth_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  linkwarden-app:
    image: ghcr.io/linkwarden/linkwarden:latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/linkwarden
      NEXTAUTH_SECRET: "$nextauth_secret"
      NEXTAUTH_URL: http://linkwarden/api/v1/auth
      NEXT_PUBLIC_DISABLE_REGISTRATION: "false"
    volumes:
      - linkwarden-data:/data/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - linkwarden-app

volumes:
  linkwarden-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://linkwarden-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
