INSTALL_DISPLAY="Typebot"
INSTALL_NOTES="Conversational form builder. Log in with admin@typebot.local. Viewer is at http://$PROJECT_NAME/viewer/."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE typebot;" 2>/dev/null || true
}

write_files() {
    local nextauth_secret enc_secret
    nextauth_secret=$(openssl rand -hex 32)
    enc_secret=$(openssl rand -hex 16)

    cat > .env << EOF
DATABASE_URL=postgresql://root:password@zeltro-postgres:5432/typebot
ENCRYPTION_SECRET=$enc_secret
NEXTAUTH_SECRET=$nextauth_secret
NEXTAUTH_URL=http://typebot
NEXT_PUBLIC_BUILDER_URL=http://typebot
NEXT_PUBLIC_VIEWER_URL=http://typebot/viewer
ADMIN_EMAIL=admin@typebot.local
DISABLE_SIGNUP=false
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  typebot-builder:
    image: baptistearno/typebot-builder:latest
    restart: unless-stopped
    env_file:
      - .env
    environment:
      PORT: "3000"

  typebot-viewer:
    image: baptistearno/typebot-viewer:latest
    restart: unless-stopped
    env_file:
      - .env
    environment:
      PORT: "3001"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - typebot-builder
      - typebot-viewer
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;

    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    location /viewer/ {
        proxy_pass http://typebot-viewer:3001/;
    }

    location / {
        proxy_pass http://typebot-builder:3000;
    }
}
NGINX
}
