INSTALL_DISPLAY="Flowise"
INSTALL_CREDENTIALS="admin / flowise123"
INSTALL_NOTES="LLM workflow builder. Connect AI models and build chatbots visually."

# Pinned deliberately: :latest was shipping a build that crash-looped on
# "TypeError: this.db.exec is not a function". 3.1.3 starts cleanly.

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  flowise-app:
    image: flowiseai/flowise:3.1.3
    restart: unless-stopped
    environment:
      PORT: "3000"
      FLOWISE_USERNAME: admin
      FLOWISE_PASSWORD: flowise123
    volumes:
      - flowise-data:/root/.flowise

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - flowise-app

volumes:
  flowise-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://flowise-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
