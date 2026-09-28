INSTALL_DISPLAY="Zulip"
INSTALL_CREDENTIALS="Register at http://$PROJECT_NAME/register/ — first user becomes admin"
INSTALL_NOTES="Open-source team chat. First startup takes ~3 minutes for initialization. Visit http://$PROJECT_NAME/ to create your organization."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE zulip;" 2>/dev/null || true
}

write_files() {
    local secret_key rabbitmq_pass memcached_pass
    secret_key=$(openssl rand -hex 32)
    rabbitmq_pass=$(openssl rand -hex 24)
    memcached_pass=$(openssl rand -hex 24)

    cat > docker-compose.yaml << EOF
services:
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - zulip-app

  zulip-app:
    image: zulip/docker-zulip:latest
    restart: unless-stopped
    environment:
      DB_HOST: zeltro-postgres
      DB_HOST_PORT: "5432"
      DB_USER: root
      DB_NAME: zulip
      SETTING_EXTERNAL_HOST: __ZELTRO_IP__
      SETTING_ZULIP_ADMINISTRATOR: admin@zulip.local
      SETTING_EMAIL_HOST: ""
      SETTING_EMAIL_HOST_USER: noreply@zulip.local
      SETTING_EMAIL_PORT: "587"
      SETTING_EMAIL_USE_SSL: "False"
      SETTING_EMAIL_USE_TLS: "True"
      SETTING_MEMCACHED_LOCATION: zulip-memcached:11211
      SETTING_RABBITMQ_HOST: zulip-rabbitmq
      SETTING_REDIS_HOST: zeltro-redis
      ZULIP_AUTH_BACKENDS: EmailAuthBackend
      SECRETS_postgres_password: password
      SECRETS_secret_key: $secret_key
      SECRETS_rabbitmq_password: $rabbitmq_pass
      SECRETS_memcached_password: $memcached_pass
    volumes:
      - zulip-data:/data
    ulimits:
      nofile:
        soft: 1000000
        hard: 1048576
    depends_on:
      - zulip-memcached
      - zulip-rabbitmq

  zulip-memcached:
    image: memcached:alpine
    restart: unless-stopped
    command:
      - sh
      - -euc
      - |
        echo 'mech_list: plain' > "\$\$SASL_CONF_PATH"
        echo "zulip@\$\$HOSTNAME:$memcached_pass" > "\$\$MEMCACHED_SASL_PWDB"
        echo "zulip@localhost:$memcached_pass" >> "\$\$MEMCACHED_SASL_PWDB"
        exec memcached -S
    environment:
      SASL_CONF_PATH: /home/memcache/memcached.conf
      MEMCACHED_SASL_PWDB: /home/memcache/memcached-sasl-db
      MEMCACHED_PASSWORD: $memcached_pass

  zulip-rabbitmq:
    image: rabbitmq:management-alpine
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: zulip
      RABBITMQ_DEFAULT_PASS: $rabbitmq_pass
    volumes:
      - zulip-rabbitmq-data:/var/lib/rabbitmq

volumes:
  zulip-data:
  zulip-rabbitmq-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    server_name zulip;
    client_max_body_size 100M;

    location / {
        proxy_pass http://zulip-app:80;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
