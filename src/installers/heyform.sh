INSTALL_DISPLAY="HeyForm"
INSTALL_CREDENTIALS="Register the first account on first visit"
INSTALL_NOTES="Uploads are stored in the heyform-assets volume; outgoing mail is not configured by default."

write_files() {
    local session_key form_key
    session_key=$(openssl rand -hex 32)
    form_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  heyform-app:
    image: heyform/community-edition:v3.0.0-rc.10
    restart: unless-stopped
    environment:
      APP_HOMEPAGE_URL: http://heyform
      APP_LISTEN_PORT: 9157
      SESSION_KEY: "$session_key"
      FORM_ENCRYPTION_KEY: "$form_key"
      MONGO_URI: "mongodb://root:password@zeltro-mongo:27017/heyform?authSource=admin"
      REDIS_HOST: zeltro-redis
      REDIS_PORT: 6379
      REDIS_DB: 0
    volumes:
      - heyform-assets:/app/static/upload

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - heyform-app

volumes:
  heyform-assets:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://heyform-app:9157;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
