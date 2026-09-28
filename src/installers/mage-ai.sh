INSTALL_DISPLAY="Mage AI"
INSTALL_CREDENTIALS="No login by default — open the editor and start building pipelines"
INSTALL_NOTES="The pipeline project lives in /home/src/zeltro_project inside the container."

# First boot scaffolds the project directory and starts the Python server.
INSTALL_READY_RETRIES=24

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  mage-app:
    image: mageai/mageai:0.9.79
    restart: unless-stopped
    command: /app/run_app.sh mage start zeltro_project
    environment:
      USER_CODE_PATH: /home/src/zeltro_project
      MAGE_DATA_DIR: /home/src/mage_data
      ENV: production
    volumes:
      - mage-src:/home/src

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - mage-app

volumes:
  mage-src:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://mage-app:6789;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_buffering off;
    }
}
NGINX
}
