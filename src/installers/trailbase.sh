INSTALL_DISPLAY="TrailBase"
INSTALL_CREDENTIALS="admin@localhost / trailbase123 (admin UI at http://trailbase/_/admin/)"
INSTALL_NOTES="TrailBase normally prints a random admin password to the log; the entrypoint here resets it to a known one instead."
INSTALL_READY_RETRIES=30

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  trailbase-app:
    image: trailbase/trailbase:0.31.3
    restart: unless-stopped
    environment:
      PUBLIC_URL: http://trailbase
    # TrailBase mints a random admin password on first boot and only prints it to
    # the log. Reset it to a known value before serving; the reset is a no-op on
    # every later start.
    entrypoint: ["/bin/sh", "-c"]
    command:
      - "/app/trail --depot /app/traildepot user change-password admin@localhost trailbase123 || true; exec /app/trail --depot /app/traildepot run --address 0.0.0.0:4000"
    volumes:
      - trailbase-depot:/app/traildepot

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - trailbase-app

volumes:
  trailbase-depot:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;

    # TrailBase serves your app at /, which is empty on a fresh depot, so point
    # the bare root at the admin dashboard instead of a 404.
    location = / {
        return 302 /_/admin/;
    }

    location / {
        proxy_pass http://trailbase-app:4000;
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
