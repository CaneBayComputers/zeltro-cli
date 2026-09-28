INSTALL_DISPLAY="Pydio Cells"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="Heavy first boot — Cells runs its headless installer from install.yml, which can take a minute or two."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"pydio_cells\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  cells-app:
    image: pydio/cells:5.0.2
    restart: unless-stopped
    environment:
      CELLS_NO_TLS: "1"
      CELLS_BIND: 0.0.0.0:8080
      CELLS_EXTERNAL: http://pydio-cells
      CELLS_WORKING_DIR: /var/cells
      CELLS_INSTALL_YAML: /pydio/config/install.yml
    volumes:
      - ./install.yml:/pydio/config/install.yml:ro
      - pydio-cells-data:/var/cells

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - cells-app

volumes:
  pydio-cells-data:
EOF

    cat > install.yml << 'YAML'
---
frontendlogin: admin
frontendpassword: admin123
frontendrepeatpassword: admin123
frontendapplicationtitle: Pydio Cells
externalurl: http://pydio-cells
dbconnectiontype: manual
dbmanualdsn: "postgres://root:password@zeltro-postgres:5432/pydio_cells?sslmode=disable&prefix={{.Meta.prefix}}&policies={{.Meta.policies}}&singular={{.Meta.singular}}"
YAML

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://cells-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_request_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
