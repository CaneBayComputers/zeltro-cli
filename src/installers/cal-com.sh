INSTALL_DISPLAY="Cal.com"
INSTALL_NOTES="Open-source scheduling platform. First startup takes ~60 seconds for migrations. Visit http://$PROJECT_NAME/ to create your account."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE calcom;" 2>/dev/null || true
}

write_files() {
    local nextauth_secret encryption_key
    nextauth_secret=$(openssl rand -hex 32)
    encryption_key=$(openssl rand -hex 16)

    cat > docker-compose.yaml << EOF
services:
  cal-com-app:
    image: calcom/cal.com:latest
    restart: unless-stopped
    environment:
      NEXT_PUBLIC_WEBAPP_URL: http://cal-com
      NEXTAUTH_URL: http://cal-com/api/auth
      NEXTAUTH_SECRET: $nextauth_secret
      CALENDSO_ENCRYPTION_KEY: $encryption_key
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/calcom
      DATABASE_DIRECT_URL: postgresql://root:password@zeltro-postgres:5432/calcom
      NEXT_PUBLIC_LICENSE_CONSENT: agree
      LICENSE_CONSENT: agree
      NODE_ENV: production
      PORT: "3000"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - cal-com-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://cal-com-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
    }
}
NGINX
}
