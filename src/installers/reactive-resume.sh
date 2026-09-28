INSTALL_DISPLAY="Reactive Resume"
INSTALL_CREDENTIALS="Register an account on first visit"
INSTALL_NOTES="No SMTP is configured, so email verification / password-reset links are printed to the container log."

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"reactive_resume\";" 2>/dev/null || true
}

write_files() {
    local auth_secret encryption_secret

    auth_secret=$(openssl rand -hex 32)
    encryption_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  reactive-resume-app:
    image: amruthpillai/reactive-resume:v5.2.5
    restart: unless-stopped
    environment:
      NODE_ENV: production
      PORT: "3000"
      APP_URL: http://reactive-resume
      DATABASE_URL: "postgresql://root:password@zeltro-postgres:5432/reactive_resume"
      AUTH_SECRET: "$auth_secret"
      ENCRYPTION_SECRET: "$encryption_secret"
      REDIS_URL: "redis://zeltro-redis:6379"
      LOCAL_STORAGE_PATH: /app/data
      FLAG_DISABLE_SIGNUPS: "false"
      FLAG_DISABLE_EMAIL_AUTH: "false"
    volumes:
      - reactive-resume-data:/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - reactive-resume-app

volumes:
  reactive-resume-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://reactive-resume-app:3000;
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
