INSTALL_DISPLAY="Argilla"
INSTALL_CREDENTIALS="argilla / argilla12345 (API key: argilla.apikey)"
INSTALL_NOTES="Bundles Elasticsearch and a background worker — budget ~3 GB RAM and ~2 minutes for the first boot."

# Elasticsearch has to go green before Argilla migrates its database, which is
# well past the default readiness window on a cold pull.
INSTALL_READY_RETRIES=48

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE argilla;" 2>/dev/null || true
}

write_files() {
    local auth_secret
    auth_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  argilla-elasticsearch:
    image: elasticsearch:8.17.0
    restart: unless-stopped
    environment:
      ES_JAVA_OPTS: -Xms512m -Xmx512m
      cluster.name: es-argilla-local
      discovery.type: single-node
      cluster.routing.allocation.disk.threshold_enabled: "false"
      xpack.security.enabled: "false"
      node.store.allow_mmap: "false"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - argilla-elastic-data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health || exit 1"]
      start_period: 60s
      interval: 10s
      timeout: 5s
      retries: 12

  argilla-app:
    image: argilla/argilla-server:v2.8.0
    restart: unless-stopped
    depends_on:
      argilla-elasticsearch:
        condition: service_healthy
    environment:
      ARGILLA_HOME_PATH: /var/lib/argilla
      ARGILLA_ELASTICSEARCH: http://argilla-elasticsearch:9200
      ARGILLA_DATABASE_URL: postgresql+asyncpg://root:password@zeltro-postgres:5432/argilla
      ARGILLA_REDIS_URL: redis://zeltro-redis:6379/12
      ARGILLA_AUTH_SECRET_KEY: "$auth_secret"
      USERNAME: argilla
      PASSWORD: argilla12345
      API_KEY: argilla.apikey
      WORKSPACE: default
    volumes:
      - argilla-data:/var/lib/argilla

  argilla-worker:
    image: argilla/argilla-server:v2.8.0
    restart: unless-stopped
    depends_on:
      argilla-elasticsearch:
        condition: service_healthy
    environment:
      ARGILLA_HOME_PATH: /var/lib/argilla
      ARGILLA_ELASTICSEARCH: http://argilla-elasticsearch:9200
      ARGILLA_DATABASE_URL: postgresql+asyncpg://root:password@zeltro-postgres:5432/argilla
      ARGILLA_REDIS_URL: redis://zeltro-redis:6379/12
      ARGILLA_AUTH_SECRET_KEY: "$auth_secret"
      BACKGROUND_NUM_WORKERS: "2"
    command: sh -c 'python -m argilla_server worker --num-workers \$\${BACKGROUND_NUM_WORKERS}'
    volumes:
      - argilla-data:/var/lib/argilla

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - argilla-app

volumes:
  argilla-data:
  argilla-elastic-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://argilla-app:6900;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
