INSTALL_DISPLAY="Lowcoder"
INSTALL_CREDENTIALS="Create the admin account on first visit"
INSTALL_NOTES="First boot takes ~60 seconds while the Java API service starts."

# The all-in-one image boots frontend + api-service + node-service under
# supervisord; the JVM is slow to come up on a cold start.
INSTALL_READY_RETRIES=24

write_files() {
    local encryption_password encryption_salt api_key_secret node_secret

    encryption_password=$(openssl rand -hex 16)
    encryption_salt=$(openssl rand -hex 8)
    api_key_secret=$(openssl rand -hex 32)
    node_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  lowcoder-app:
    image: lowcoderorg/lowcoder-ce:2.7.6
    restart: unless-stopped
    environment:
      # Use the shared Zeltro services instead of the bundled mongo/redis
      LOWCODER_MONGODB_ENABLED: "false"
      LOWCODER_REDIS_ENABLED: "false"
      LOWCODER_MONGODB_URL: "mongodb://root:password@zeltro-mongo:27017/lowcoder?authSource=admin"
      LOWCODER_REDIS_URL: "redis://zeltro-redis:6379"
      LOWCODER_API_SERVICE_ENABLED: "true"
      LOWCODER_NODE_SERVICE_ENABLED: "true"
      LOWCODER_FRONTEND_ENABLED: "true"
      LOWCODER_PUBLIC_URL: "http://lowcoder"
      LOWCODER_CORS_DOMAINS: "*"
      LOWCODER_EMAIL_SIGNUP_ENABLED: "true"
      LOWCODER_EMAIL_AUTH_ENABLED: "true"
      LOWCODER_DB_ENCRYPTION_PASSWORD: "$encryption_password"
      LOWCODER_DB_ENCRYPTION_SALT: "$encryption_salt"
      LOWCODER_API_KEY_SECRET: "$api_key_secret"
      LOWCODER_NODE_SERVICE_SECRET: "$node_secret"
      LOWCODER_NODE_SERVICE_SECRET_SALT: "lowcoder.org"
      LOWCODER_MAX_REQUEST_SIZE: 20mb
      LOWCODER_MAX_QUERY_TIMEOUT: 120
      LOWCODER_PUID: "1000"
      LOWCODER_PGID: "1000"
    volumes:
      - lowcoder-stacks:/lowcoder-stacks
      - lowcoder-assets:/lowcoder/assets

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - lowcoder-app

volumes:
  lowcoder-stacks:
  lowcoder-assets:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://lowcoder-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
