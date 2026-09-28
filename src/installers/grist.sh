INSTALL_DISPLAY="Grist"
INSTALL_CREDENTIALS="Signed in automatically as admin@example.com"
INSTALL_NOTES="GRIST_IN_SERVICE=true skips the /boot key gate that otherwise wedges a headless install."
INSTALL_READY_RETRIES=30

write_files() {
    local session_secret
    session_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  grist-app:
    image: gristlabs/grist-oss:1.7.17
    restart: unless-stopped
    environment:
      GRIST_SESSION_SECRET: "$session_secret"
      GRIST_DEFAULT_EMAIL: admin@example.com
      GRIST_ADMIN_EMAIL: admin@example.com
      APP_HOME_URL: http://grist
      GRIST_SINGLE_ORG: docs
      GRIST_SANDBOX_FLAVOR: gvisor
      GRIST_FORCE_LOGIN: "false"
      GRIST_IN_SERVICE: "true"
    volumes:
      - grist-data:/persist

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - grist-app

volumes:
  grist-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://grist-app:8484;
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
