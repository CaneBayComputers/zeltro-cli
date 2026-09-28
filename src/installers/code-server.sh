INSTALL_DISPLAY="Code-Server"
INSTALL_CREDENTIALS="Password: codeserver123"
INSTALL_NOTES="VS Code in a browser. Change the default password by editing the PASSWORD environment variable."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  code-server-app:
    image: codercom/code-server:latest
    restart: unless-stopped
    environment:
      PASSWORD: codeserver123
    volumes:
      - code-server-data:/home/coder/.local/share/code-server
      - code-server-workspace:/home/coder/project

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - code-server-app

volumes:
  code-server-data:
  code-server-workspace:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://code-server-app:8080;
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
