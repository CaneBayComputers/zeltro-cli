INSTALL_DISPLAY="Dify"
INSTALL_CREDENTIALS="Set admin password on first visit (uses INIT_PASSWORD=DifyAdmin123)"
INSTALL_NOTES="AI workflow builder. First startup takes ~60 seconds for DB migrations. Visit http://$PROJECT_NAME/ to initialize."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE dify;" 2>/dev/null || true
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE dify_plugin;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -base64 42)

    cat > .env << EOF
SECRET_KEY=$secret_key
INIT_PASSWORD=DifyAdmin123
DEPLOY_ENV=PRODUCTION

DB_TYPE=postgresql
DB_USERNAME=root
DB_PASSWORD=password
DB_HOST=zeltro-postgres
DB_PORT=5432
DB_DATABASE=dify

REDIS_HOST=zeltro-redis
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=
CELERY_BROKER_URL=redis://zeltro-redis:6379/1

STORAGE_TYPE=local
OPENDAL_SCHEME=fs
OPENDAL_FS_ROOT=storage

VECTOR_STORE=weaviate
WEAVIATE_ENDPOINT=http://weaviate:8080
WEAVIATE_API_KEY=WVF5YThaHlkYwhGUSmCRgsX3tD5ngdN8pkih

MIGRATION_ENABLED=true

CODE_EXECUTION_ENDPOINT=http://dify-sandbox:8194
CODE_EXECUTION_API_KEY=dify-sandbox

NEXT_PUBLIC_SOCKET_URL=ws://dify
TRIGGER_URL=http://dify

CONSOLE_CORS_ALLOW_ORIGINS=*
WEB_API_CORS_ALLOW_ORIGINS=*

SANDBOX_API_KEY=dify-sandbox
SANDBOX_GIN_MODE=release
SANDBOX_ENABLE_NETWORK=false
EOF

    cat > docker-compose.yaml << 'EOF'
x-api-env: &api-env
  env_file: .env
  volumes:
    - dify-storage:/app/api/storage

services:
  api:
    image: langgenius/dify-api:latest
    restart: always
    <<: *api-env
    environment:
      MODE: api
    depends_on:
      - weaviate

  worker:
    image: langgenius/dify-api:latest
    restart: always
    <<: *api-env
    environment:
      MODE: worker
    depends_on:
      - weaviate

  worker_beat:
    image: langgenius/dify-api:latest
    restart: always
    <<: *api-env
    environment:
      MODE: beat

  web:
    image: langgenius/dify-web:latest
    restart: always
    env_file: .env

  dify-sandbox:
    image: langgenius/dify-sandbox:latest
    restart: always
    environment:
      API_KEY: dify-sandbox
      GIN_MODE: release
      WORKER_TIMEOUT: 15
      ENABLE_NETWORK: "false"
      SANDBOX_PORT: 8194
    volumes:
      - dify-sandbox-deps:/dependencies

  weaviate:
    image: semitechnologies/weaviate:1.27.0
    restart: always
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "true"
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      DEFAULT_VECTORIZER_MODULE: none
      CLUSTER_HOSTNAME: node1
    volumes:
      - dify-weaviate-data:/var/lib/weaviate

  nginx:
    image: nginx:alpine
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
      - web

volumes:
  dify-storage:
  dify-sandbox-deps:
  dify-weaviate-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;

    location /console/api {
        proxy_pass http://api:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    location /api {
        proxy_pass http://api:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    location /v1 {
        proxy_pass http://api:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
    }

    location /files {
        proxy_pass http://api:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
    }

    location / {
        proxy_pass http://web:3000;
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
