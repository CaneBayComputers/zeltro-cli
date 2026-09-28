INSTALL_DISPLAY="ownCloud"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="First boot runs occ maintenance:install — allow a minute or two before the login page appears."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"owncloud\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  owncloud-app:
    image: owncloud/server:10.16.4
    restart: unless-stopped
    environment:
      # __ZELTRO_IP__ / __ZELTRO_PROJECT__ are filled in by zeltro install once
      # the project has its address: the IP for browsers, the name for containers.
      OWNCLOUD_DOMAIN: __ZELTRO_IP__
      OWNCLOUD_TRUSTED_DOMAINS: "__ZELTRO_PROJECT__,__ZELTRO_IP__"
      OWNCLOUD_DB_TYPE: pgsql
      OWNCLOUD_DB_HOST: zeltro-postgres
      OWNCLOUD_DB_NAME: owncloud
      OWNCLOUD_DB_USERNAME: root
      OWNCLOUD_DB_PASSWORD: password
      OWNCLOUD_ADMIN_USERNAME: admin
      OWNCLOUD_ADMIN_PASSWORD: admin123
      OWNCLOUD_OVERWRITE_PROTOCOL: http
      OWNCLOUD_REDIS_ENABLED: "false"
    volumes:
      - owncloud-files:/mnt/data

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - owncloud-app

volumes:
  owncloud-files:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://owncloud-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
