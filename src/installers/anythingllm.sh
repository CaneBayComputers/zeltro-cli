INSTALL_DISPLAY="AnythingLLM"
INSTALL_CREDENTIALS="run the on-screen setup wizard on first visit"
INSTALL_NOTES="Pick an LLM provider and embedder in the first-run wizard; the built-in LanceDB vector store needs no extra service."

write_files() {
    local jwt_secret sig_key sig_salt

    jwt_secret=$(openssl rand -hex 32)
    sig_key=$(openssl rand -hex 32)
    sig_salt=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  anythingllm-app:
    image: mintplexlabs/anythingllm:1.15.0
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    environment:
      SERVER_PORT: "3001"
      STORAGE_DIR: /app/server/storage
      JWT_SECRET: "$jwt_secret"
      SIG_KEY: "$sig_key"
      SIG_SALT: "$sig_salt"
      DISABLE_TELEMETRY: "true"
      VECTOR_DB: lancedb
    volumes:
      - anythingllm-storage:/app/server/storage

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - anythingllm-app

volumes:
  anythingllm-storage:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 512M;
    location / {
        proxy_pass http://anythingllm-app:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
