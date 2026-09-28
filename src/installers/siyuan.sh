INSTALL_DISPLAY="SiYuan"
INSTALL_CREDENTIALS="No login — the lock screen is bypassed"
INSTALL_NOTES="SiYuan has no user accounts. To lock it, drop SIYUAN_ACCESS_AUTH_CODE_BYPASS and add --accessAuthCode=<code> to the command."
INSTALL_READY_RETRIES=30

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  siyuan-app:
    image: b3log/siyuan:v3.7.3
    restart: unless-stopped
    # 'serve' became mandatory in v3.7.0 — without it the container exits.
    command: ['serve', '--workspace=/siyuan/workspace/']
    environment:
      PUID: 1000
      PGID: 1000
      SIYUAN_LANG: en
      # With an access auth code set, SiYuan answers / with a bare 401 JSON body
      # instead of a login page, which fails the readiness probe and looks broken
      # in a browser. Bypass it; Zeltro projects are local-network only.
      # Note the auth code must ALSO be absent from the command — a command-line
      # --accessAuthCode is written into conf.json and wins over this variable.
      SIYUAN_ACCESS_AUTH_CODE_BYPASS: "true"
    volumes:
      - siyuan-workspace:/siyuan/workspace

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - siyuan-app

volumes:
  siyuan-workspace:
EOF

    # SiYuan authenticates over /ws; URL rewriting breaks its auth, so pass
    # everything through untouched.
    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 500M;
    location / {
        proxy_pass http://siyuan-app:6806;
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
