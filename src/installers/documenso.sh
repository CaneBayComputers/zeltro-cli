INSTALL_DISPLAY="Documenso"
INSTALL_CREDENTIALS="Register on first visit"
INSTALL_NOTES="A self-signed signing certificate is generated into cert.p12 — replace it before signing anything you care about."
INSTALL_READY_RETRIES=60

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE documenso;" 2>/dev/null || true
}

write_files() {
    local nextauth_secret enc_key enc_secondary

    nextauth_secret=$(openssl rand -hex 32)
    enc_key=$(openssl rand -hex 32)
    enc_secondary=$(openssl rand -hex 32)

    # Without a readable PKCS#12 bundle Documenso boots but reports "Certificate
    # not found" and cannot sign anything. Generate a throwaway self-signed one
    # using SHA1/3DES, which is what its node-forge based reader can parse —
    # OpenSSL 3's AES-256 default produces a file Documenso rejects.
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout documenso-signing.key -out documenso-signing.crt \
        -subj "/CN=Documenso Zeltro Dev" >/dev/null 2>&1
    openssl pkcs12 -export -out cert.p12 \
        -inkey documenso-signing.key -in documenso-signing.crt \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
        -passout pass: >/dev/null 2>&1
    rm -f documenso-signing.key documenso-signing.crt
    # openssl writes the bundle 0600 as the invoking user; the container runs as
    # uid 1001, so without this it mounts fine and still reads as "not found".
    chmod 644 cert.p12

    cat > docker-compose.yaml << EOF
services:
  documenso-app:
    image: ghcr.io/documenso/documenso:v2.16.0
    restart: unless-stopped
    environment:
      PORT: 3000
      NEXTAUTH_SECRET: "$nextauth_secret"
      NEXT_PRIVATE_ENCRYPTION_KEY: "$enc_key"
      NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY: "$enc_secondary"
      NEXT_PUBLIC_WEBAPP_URL: http://documenso
      NEXT_PRIVATE_INTERNAL_WEBAPP_URL: http://localhost:3000
      NEXT_PRIVATE_DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/documenso
      NEXT_PRIVATE_DIRECT_DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/documenso
      NEXT_PUBLIC_UPLOAD_TRANSPORT: database
      NEXT_PRIVATE_SMTP_TRANSPORT: smtp-auth
      NEXT_PRIVATE_SMTP_HOST: zeltro-mailhog
      NEXT_PRIVATE_SMTP_PORT: 1025
      NEXT_PRIVATE_SMTP_SECURE: "false"
      NEXT_PRIVATE_SMTP_UNSAFE_IGNORE_TLS: "true"
      NEXT_PRIVATE_SMTP_FROM_NAME: Documenso
      NEXT_PRIVATE_SMTP_FROM_ADDRESS: documenso@example.com
      NEXT_PRIVATE_SIGNING_TRANSPORT: local
      NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH: /opt/documenso/cert.p12
    volumes:
      - ./cert.p12:/opt/documenso/cert.p12:ro

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - documenso-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://documenso-app:3000;
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
