INSTALL_DISPLAY="NetBox"
INSTALL_CREDENTIALS="admin / admin"
INSTALL_NOTES="First startup takes ~60 seconds for database migrations. Visit http://$PROJECT_NAME/ to access."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE netbox;" 2>/dev/null || true
}

# NetBox runs Django migrations and collectstatic on first boot; measured at
# ~4 minutes on a clean box, well past the default 75s readiness window.
INSTALL_READY_RETRIES=48

write_files() {
    local secret_key
    # SECRET_KEY must be at least 50 chars; use hex (only alphanumeric, never stripped)
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  netbox-app:
    image: netboxcommunity/netbox:latest
    restart: unless-stopped
    environment:
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      DB_USER: root
      DB_PASSWORD: password
      DB_NAME: netbox
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      REDIS_PASSWORD: ""
      REDIS_DATABASE: "4"
      REDIS_INSECURE_SKIP_TLS_VERIFY: "false"
      REDIS_SSL: "false"
      REDIS_CACHE_HOST: zeltro-redis
      REDIS_CACHE_PORT: "6379"
      REDIS_CACHE_PASSWORD: ""
      REDIS_CACHE_DATABASE: "5"
      REDIS_CACHE_INSECURE_SKIP_TLS_VERIFY: "false"
      REDIS_CACHE_SSL: "false"
      SECRET_KEY: $secret_key
      ALLOWED_HOSTS: "*"
      CSRF_TRUSTED_ORIGINS: http://netbox
      SKIP_SUPERUSER: "false"
      SUPERUSER_NAME: admin
      SUPERUSER_EMAIL: admin@example.com
      SUPERUSER_PASSWORD: admin
      SUPERUSER_API_TOKEN: $(openssl rand -hex 20)
    volumes:
      - netbox-media:/opt/netbox/netbox/media
      - netbox-reports:/opt/netbox/netbox/reports
      - netbox-scripts:/opt/netbox/netbox/scripts

  netbox-worker:
    image: netboxcommunity/netbox:latest
    restart: unless-stopped
    command:
      - /opt/netbox/venv/bin/python
      - /opt/netbox/netbox/manage.py
      - rqworker
    depends_on:
      - netbox-app
    environment:
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      DB_USER: root
      DB_PASSWORD: password
      DB_NAME: netbox
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      REDIS_PASSWORD: ""
      REDIS_DATABASE: "4"
      REDIS_INSECURE_SKIP_TLS_VERIFY: "false"
      REDIS_SSL: "false"
      REDIS_CACHE_HOST: zeltro-redis
      REDIS_CACHE_PORT: "6379"
      REDIS_CACHE_PASSWORD: ""
      REDIS_CACHE_DATABASE: "5"
      REDIS_CACHE_INSECURE_SKIP_TLS_VERIFY: "false"
      REDIS_CACHE_SSL: "false"
      SECRET_KEY: $secret_key
      ALLOWED_HOSTS: "*"
      SKIP_SUPERUSER: "true"
    volumes:
      - netbox-media:/opt/netbox/netbox/media
      - netbox-reports:/opt/netbox/netbox/reports
      - netbox-scripts:/opt/netbox/netbox/scripts

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - netbox-app

volumes:
  netbox-media:
  netbox-reports:
  netbox-scripts:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://netbox-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
NGINX
}
