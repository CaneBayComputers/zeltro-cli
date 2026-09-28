INSTALL_DISPLAY="LibreChat"
INSTALL_CREDENTIALS="register on first visit (first account is a normal user; promote via the CLI)"
INSTALL_NOTES="No model providers are configured — add an API key (e.g. OPENAI_API_KEY) to the compose environment to get endpoints."

write_files() {
    local creds_key creds_iv jwt_secret jwt_refresh

    creds_key=$(openssl rand -hex 32)
    creds_iv=$(openssl rand -hex 16)
    jwt_secret=$(openssl rand -hex 32)
    jwt_refresh=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  librechat-app:
    image: ghcr.io/danny-avila/librechat:v0.8.7
    restart: unless-stopped
    environment:
      HOST: 0.0.0.0
      PORT: "3080"
      MONGO_URI: mongodb://root:password@zeltro-mongo:27017/librechat?authSource=admin
      DOMAIN_CLIENT: http://librechat
      DOMAIN_SERVER: http://librechat
      NO_INDEX: "true"
      SEARCH: "false"
      ALLOW_REGISTRATION: "true"
      ALLOW_EMAIL_LOGIN: "true"
      ALLOW_SOCIAL_LOGIN: "false"
      CREDS_KEY: "$creds_key"
      CREDS_IV: "$creds_iv"
      JWT_SECRET: "$jwt_secret"
      JWT_REFRESH_SECRET: "$jwt_refresh"
      SESSION_EXPIRY: "900000"
      REFRESH_TOKEN_EXPIRY: "604800000"
    volumes:
      - librechat-images:/app/client/public/images
      - librechat-uploads:/app/uploads
      - librechat-logs:/app/logs

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - librechat-app

volumes:
  librechat-images:
  librechat-uploads:
  librechat-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 512M;
    location / {
        proxy_pass http://librechat-app:3080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
