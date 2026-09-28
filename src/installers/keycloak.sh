INSTALL_DISPLAY="Keycloak"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="First boot runs the schema build and migrations — give it a minute before the admin console answers."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"keycloak\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  keycloak-app:
    image: quay.io/keycloak/keycloak:26.7.1
    restart: unless-stopped
    command: ["start", "--optimized=false"]
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://zeltro-postgres:5432/keycloak
      KC_DB_USERNAME: root
      KC_DB_PASSWORD: password
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: admin123
      KC_HTTP_ENABLED: "true"
      KC_HTTP_PORT: "8080"
      KC_HOSTNAME: http://keycloak
      KC_HOSTNAME_STRICT: "false"
      KC_HOSTNAME_BACKCHANNEL_DYNAMIC: "false"
      KC_PROXY_HEADERS: xforwarded
      KC_HEALTH_ENABLED: "true"
    volumes:
      - keycloak-data:/opt/keycloak/data

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - keycloak-app

volumes:
  keycloak-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    large_client_header_buffers 4 32k;
    location / {
        proxy_pass http://keycloak-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 80;
        proxy_read_timeout 300s;
    }
}
NGINX
}
