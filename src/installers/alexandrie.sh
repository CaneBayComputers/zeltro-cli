INSTALL_DISPLAY="Alexandrie"
INSTALL_CREDENTIALS="register the first account on first visit"
INSTALL_NOTES="nginx fronts three services: / -> Nuxt frontend, /api/ -> Go backend, /alexandrie/ -> RustFS object storage."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS alexandrie CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

write_files() {
    local jwt_secret s3_key s3_secret
    jwt_secret=$(openssl rand -hex 32)
    s3_key=$(openssl rand -hex 8)
    s3_secret=$(openssl rand -hex 24)

    cat > docker-compose.yaml << EOF
services:
  alexandrie-rustfs:
    image: rustfs/rustfs:1.0.0-beta.12
    restart: unless-stopped
    environment:
      RUSTFS_ACCESS_KEY: "$s3_key"
      RUSTFS_SECRET_KEY: "$s3_secret"
      RUSTFS_CONSOLE_ENABLE: "false"
      RUSTFS_LOG_LEVEL: error
    volumes:
      - alexandrie-rustfs-data:/data
      - alexandrie-rustfs-logs:/logs

  alexandrie-backend:
    image: ghcr.io/smaug6739/alexandrie-backend:v8.11.0
    restart: unless-stopped
    depends_on:
      - alexandrie-rustfs
    environment:
      BACKEND_PORT: "8201"
      GIN_MODE: release
      JWT_SECRET: "$jwt_secret"
      COOKIE_DOMAIN: ""
      FRONTEND_URL: http://alexandrie
      ALLOW_UNSECURE: "true"
      CONFIG_DISABLE_SIGNUP: "false"
      CONFIG_DISABLE_NATIVE_LOGIN: "false"
      DATABASE_HOST: zeltro-mariadb
      DATABASE_PORT: "3306"
      DATABASE_NAME: alexandrie
      DATABASE_USER: root
      DATABASE_PASSWORD: ""
      MINIO_ENDPOINT: alexandrie-rustfs:9000
      MINIO_PUBLIC_URL: http://alexandrie
      MINIO_SECURE: "false"
      MINIO_ACCESSKEY: "$s3_key"
      MINIO_SECRETKEY: "$s3_secret"
      MINIO_BUCKET: alexandrie
      SMTP_HOST: ""
      SMTP_MAIL: ""
      SMTP_MAIL_FROM: ""
      SMTP_PASSWORD: ""

  alexandrie-frontend:
    image: ghcr.io/smaug6739/alexandrie-frontend:v8.11.0
    restart: unless-stopped
    depends_on:
      - alexandrie-backend
    environment:
      PORT: "8200"
      NUXT_PUBLIC_CONFIG_DISABLE_SIGNUP_PAGE: "false"
      NUXT_PUBLIC_CONFIG_DISABLE_LANDING_PAGE: "false"
      NUXT_PUBLIC_BASE_API: http://alexandrie/api
      NUXT_PUBLIC_BASE_CDN: http://alexandrie
      NUXT_PUBLIC_CDN_ENDPOINT: /alexandrie/
      NUXT_PUBLIC_BASE_URL: http://alexandrie

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - alexandrie-frontend

volumes:
  alexandrie-rustfs-data:
  alexandrie-rustfs-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;

    location /api/ {
        proxy_pass http://alexandrie-backend:8201/;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }

    location /alexandrie/ {
        proxy_pass http://alexandrie-rustfs:9000/alexandrie/;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://alexandrie-frontend:8200;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
