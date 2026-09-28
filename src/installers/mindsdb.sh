INSTALL_DISPLAY="MindsDB"
INSTALL_CREDENTIALS="none — the editor is open on the local network"
INSTALL_NOTES="Large image (multi-GB) and a slow first boot; the SQL editor answers once the HTTP API finishes loading handlers."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  mindsdb-app:
    image: mindsdb/mindsdb:v26.1.0
    restart: unless-stopped
    environment:
      MINDSDB_STORAGE_DIR: /root/mdb_storage
      MINDSDB_DOCKER_ENV: "1"
      FLASK_DEBUG: "0"
    volumes:
      - mindsdb-storage:/root/mdb_storage

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - mindsdb-app

volumes:
  mindsdb-storage:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 256M;
    location / {
        proxy_pass http://mindsdb-app:47334;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 900s;
    }
}
NGINX
}
