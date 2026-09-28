INSTALL_DISPLAY="Portainer CE"
INSTALL_NOTES="Create your admin account on first visit — the setup wizard locks after 5 minutes."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  portainer-app:
    image: portainer/portainer-ce:latest
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer-data:/data
    networks:
      default:

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      default:
    depends_on:
      - portainer-app

volumes:
  portainer-data:

networks:
  default:
    external: true
    name: zeltro-cli_vpc
EOF

    cat > nginx.conf << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://portainer-app:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Connection "";
    }
}
EOF
}
