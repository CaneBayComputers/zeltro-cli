INSTALL_DISPLAY="Odoo"
INSTALL_CREDENTIALS="Create the database on first visit (master password: admin123)"
INSTALL_NOTES="First visit shows Odoo's database manager — create a database, then log in with the admin email/password you set there."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  odoo-app:
    image: odoo:19.0
    restart: unless-stopped
    environment:
      HOST: zeltro-postgres
      PORT: 5432
      USER: root
      PASSWORD: password
    command: >
      odoo
      --db_host=zeltro-postgres
      --db_port=5432
      --db_user=root
      --db_password=password
      --proxy-mode
      --without-demo=all
    volumes:
      - odoo-data:/var/lib/odoo
      - odoo-addons:/mnt/extra-addons

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - odoo-app

volumes:
  odoo-data:
  odoo-addons:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;

    location / {
        proxy_pass http://odoo-app:8069;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 720s;
        proxy_send_timeout 720s;
    }

    location /websocket {
        proxy_pass http://odoo-app:8072;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 720s;
    }
}
NGINX
}
