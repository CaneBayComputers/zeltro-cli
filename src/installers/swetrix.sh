INSTALL_DISPLAY="Swetrix Analytics"
INSTALL_CREDENTIALS="Register the first account on first visit"
INSTALL_NOTES="Ships a ClickHouse sidecar for event storage; first startup takes ~60 seconds. Only the first registration is allowed."

write_files() {
    local secret_key clickhouse_password
    secret_key=$(openssl rand -hex 32)
    clickhouse_password=$(openssl rand -hex 16)

    mkdir -p clickhouse

    cat > clickhouse/preserve-ram-config.xml << 'EOF'
<clickhouse>
  <mark_cache_size>536870912</mark_cache_size>
  <concurrent_threads_soft_limit_num>1</concurrent_threads_soft_limit_num>
</clickhouse>
EOF

    cat > clickhouse/preserve-ram-user.xml << 'EOF'
<clickhouse>
  <profiles>
    <default>
      <max_block_size>2048</max_block_size>
      <max_download_threads>1</max_download_threads>
      <input_format_parallel_parsing>0</input_format_parallel_parsing>
      <output_format_parallel_formatting>0</output_format_parallel_formatting>
    </default>
  </profiles>
</clickhouse>
EOF

    cat > clickhouse/reduce-logs.xml << 'EOF'
<clickhouse>
  <logger>
    <level>warning</level>
    <console>true</console>
  </logger>
  <query_thread_log remove="remove"/>
  <query_log remove="remove"/>
  <text_log remove="remove"/>
  <trace_log remove="remove"/>
  <metric_log remove="remove"/>
  <asynchronous_metric_log remove="remove"/>
  <session_log remove="remove"/>
  <part_log remove="remove"/>
  <processors_profile_log remove="remove"/>
  <asynchronous_insert_log remove="remove"/>
  <query_metric_log remove="remove"/>
  <opentelemetry_span_log remove="remove"/>
</clickhouse>
EOF

    cat > clickhouse/disable-user-logging.xml << 'EOF'
<clickhouse>
  <profiles>
    <default>
      <log_queries>0</log_queries>
      <log_query_threads>0</log_query_threads>
    </default>
  </profiles>
</clickhouse>
EOF

    cat > docker-compose.yaml << EOF
services:
  swetrix-clickhouse:
    image: clickhouse/clickhouse-server:25.8-alpine
    restart: unless-stopped
    environment:
      CLICKHOUSE_DB: analytics
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: "$clickhouse_password"
    cap_add:
      - SYS_NICE
    volumes:
      - swetrix-events-data:/var/lib/clickhouse
      - ./clickhouse/reduce-logs.xml:/etc/clickhouse-server/config.d/reduce-logs.xml:ro
      - ./clickhouse/disable-user-logging.xml:/etc/clickhouse-server/users.d/disable-user-logging.xml:ro
      - ./clickhouse/preserve-ram-config.xml:/etc/clickhouse-server/config.d/preserve-ram-config.xml:ro
      - ./clickhouse/preserve-ram-user.xml:/etc/clickhouse-server/users.d/preserve-ram-user.xml:ro
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 -O - http://127.0.0.1:8123/ping || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 60s

  swetrix-api:
    image: swetrix/swetrix-api:v5.4.1
    restart: unless-stopped
    environment:
      SECRET_KEY_BASE: "$secret_key"
      DISABLE_REGISTRATION: "false"
      REDIS_HOST: zeltro-redis
      REDIS_PORT: 6379
      CLICKHOUSE_HOST: http://swetrix-clickhouse
      CLICKHOUSE_PORT: 8123
      CLICKHOUSE_USER: default
      CLICKHOUSE_DATABASE: analytics
      CLICKHOUSE_PASSWORD: "$clickhouse_password"
      SMTP_MOCK: "true"
    depends_on:
      swetrix-clickhouse:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://127.0.0.1:5005/ping || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  swetrix-fe:
    image: swetrix/swetrix-fe:v5.4.1
    restart: unless-stopped
    environment:
      BASE_URL: http://swetrix
    depends_on:
      - swetrix-api

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - swetrix-fe

volumes:
  swetrix-events-data:
EOF

    cat > nginx.conf << 'NGINX'
map $http_upgrade $connection_upgrade {
  default upgrade;
  ""      close;
}

server {
  listen 80;
  server_name _;

  # Keep the /backend/ prefix; this is how the UI reaches the Swetrix API.
  location /backend/ {
    proxy_pass http://swetrix-api:5005/;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_buffering on;
    proxy_buffer_size 256k;
    proxy_buffers 64 512k;
    proxy_busy_buffers_size 16m;
  }

  location / {
    proxy_pass http://swetrix-fe:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_buffering on;
    proxy_buffer_size 256k;
    proxy_buffers 64 512k;
    proxy_busy_buffers_size 16m;
  }
}
NGINX
}
