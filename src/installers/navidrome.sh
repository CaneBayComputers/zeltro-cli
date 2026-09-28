INSTALL_DISPLAY="Navidrome"
INSTALL_CREDENTIALS="create the admin account on first visit"
INSTALL_NOTES="Drop music into the navidrome-music volume (/music); the scanner picks it up on the next sweep."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  navidrome-app:
    image: deluan/navidrome:0.63.2
    restart: unless-stopped
    environment:
      ND_PORT: "4533"
      ND_MUSICFOLDER: /music
      ND_DATAFOLDER: /data
      ND_SCANSCHEDULE: 1h
      ND_LOGLEVEL: info
      ND_SESSIONTIMEOUT: 24h
      ND_BASEURL: ""
    volumes:
      - navidrome-data:/data
      - navidrome-music:/music

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - navidrome-app

volumes:
  navidrome-data:
  navidrome-music:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://navidrome-app:4533;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
