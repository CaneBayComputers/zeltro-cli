INSTALL_DISPLAY="Chibisafe"
INSTALL_CREDENTIALS="admin / admin"
INSTALL_NOTES="Change the admin password on first login — it is admin/admin out of the box."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  chibisafe-frontend:
    image: chibisafe/chibisafe:v6.5.5
    restart: unless-stopped
    environment:
      BASE_API_URL: http://chibisafe-server:8000

  chibisafe-server:
    image: chibisafe/chibisafe-server:v6.5.5
    restart: unless-stopped
    volumes:
      - chibisafe-database:/app/database
      - chibisafe-uploads:/app/uploads
      - chibisafe-logs:/app/logs

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - chibisafe-uploads:/app/uploads:ro
    depends_on:
      - chibisafe-frontend
      - chibisafe-server

volumes:
  chibisafe-database:
  chibisafe-uploads:
  chibisafe-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;

    location /api/ {
        proxy_pass http://chibisafe-server:8000;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 900s;
        proxy_send_timeout 900s;
    }

    location /docs {
        proxy_pass http://chibisafe-server:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Exact "/" must never hit the uploads root — try_files would resolve it to
    # a directory and nginx would answer 403 instead of rendering the app.
    location = / {
        proxy_pass http://chibisafe-frontend:8001;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        root /app/uploads;
        try_files $uri @frontend;
    }

    location @frontend {
        proxy_pass http://chibisafe-frontend:8001;
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
