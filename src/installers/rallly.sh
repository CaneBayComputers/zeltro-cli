INSTALL_DISPLAY="Rallly"
INSTALL_CREDENTIALS="register on first visit (use admin@example.com to claim admin)"
INSTALL_NOTES="Sign-in sends a 6-digit code by email — read it in MailHog or with 'docker logs rallly-app'."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE rallly;" 2>/dev/null || true
}

write_files() {
    local secret_password
    # SECRET_PASSWORD must be at least 32 characters
    secret_password=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  rallly-app:
    image: lukevella/rallly:4.12.1
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://root:password@zeltro-postgres:5432/rallly
      SECRET_PASSWORD: "$secret_password"
      NEXT_PUBLIC_BASE_URL: http://rallly
      SUPPORT_EMAIL: admin@example.com
      NOREPLY_EMAIL: noreply@rallly.local
      NOREPLY_EMAIL_NAME: Rallly
      INITIAL_ADMIN_EMAIL: admin@example.com
      EMAIL_LOGIN_ENABLED: "true"
      REGISTRATION_ENABLED: "true"
      SMTP_HOST: zeltro-mailhog
      SMTP_PORT: "1025"
      SMTP_SECURE: "false"
      SMTP_TLS_ENABLED: "false"
      SMTP_REJECT_UNAUTHORIZED: "false"

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - rallly-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://rallly-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }
}
NGINX
}
