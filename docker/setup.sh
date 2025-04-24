#!/bin/bash
set -e

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Odoo SFU Docker Setup Script${NC}"
echo "This script will help you set up the Odoo SFU in Docker."

# Set the directory to docker folder
cd "$(dirname "$0")"

# Create necessary directories
mkdir -p nginx/conf.d nginx/ssl

# Check if default.conf already exists, create if not
if [ ! -f nginx/conf.d/default.conf ]; then
    echo -e "${YELLOW}Creating Nginx configuration...${NC}"
    cat > nginx/conf.d/default.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;

    # Redirect all HTTP traffic to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name _;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    # Security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # HSTS (optional, comment if causing issues)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Forward WebSocket connections to SFU
    location / {
        proxy_pass http://sfu:8070;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
}
EOF
    echo -e "${GREEN}Nginx configuration created.${NC}"
fi

# Initialize .env file if it doesn't exist
touch .env.new

# Get public IP if not already known
if [ -f .env ] && grep -q "PUBLIC_IP" .env; then
    PUBLIC_IP=$(grep PUBLIC_IP .env | cut -d= -f2)
    echo -e "${YELLOW}Found existing PUBLIC_IP: ${PUBLIC_IP}${NC}"
else
    echo -e "${YELLOW}Detecting public IP address...${NC}"
    PUBLIC_IP=$(curl -s https://ipinfo.io/ip || curl -s https://api.ipify.org)
    if [ -z "$PUBLIC_IP" ]; then
        echo -e "${YELLOW}Could not auto-detect public IP. Please enter it manually:${NC}"
        read -p "Public IP: " PUBLIC_IP
    else
        echo -e "${GREEN}Detected public IP: ${PUBLIC_IP}${NC}"
    fi
    echo "PUBLIC_IP=${PUBLIC_IP}" >> .env.new
fi

# Generate AUTH_KEY if not exists
if [ -f .env ] && grep -q "AUTH_KEY" .env; then
    AUTH_KEY=$(grep AUTH_KEY .env | cut -d= -f2)
    echo -e "${YELLOW}Found existing AUTH_KEY.${NC}"
    echo "AUTH_KEY=${AUTH_KEY}" >> .env.new
else
    echo -e "${YELLOW}Generating new AUTH_KEY...${NC}"
    AUTH_KEY=$(openssl rand -base64 32)
    echo -e "${GREEN}Generated new AUTH_KEY.${NC}"
    echo "AUTH_KEY=${AUTH_KEY}" >> .env.new
fi

# Determine number of CPU cores for NUM_WORKERS
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
RECOMMENDED_WORKERS=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
echo -e "${YELLOW}System has ${CPU_CORES} CPU cores. Recommended NUM_WORKERS: ${RECOMMENDED_WORKERS}${NC}"

# Add optional configuration with defaults if not already in .env
if [ -f .env ]; then
    # Transfer any other existing settings not already handled
    grep -v "PUBLIC_IP\|AUTH_KEY\|NUM_WORKERS" .env >> .env.new
fi

# Add default values if not already set
cat >> .env.new << EOF
# Required connection settings
PROXY=1
RTC_MIN_PORT=40000
RTC_MAX_PORT=49999

# Performance settings
NUM_WORKERS=${RECOMMENDED_WORKERS}
MAX_BITRATE_IN=8000000
MAX_BITRATE_OUT=10000000
MAX_VIDEO_BITRATE=4000000
CHANNEL_SIZE=100

# Logging settings
LOG_LEVEL=info
LOG_TIMESTAMP=true
LOG_COLOR=true

# Nginx port settings (optional)
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443

# Use HTTPS
USE_HTTPS=true
EOF

# Replace old .env with new one
mv .env.new .env

echo -e "${GREEN}Configuration saved to .env file.${NC}"
echo -e "${YELLOW}Important: Keep your AUTH_KEY secure - you'll need it to connect Odoo to this SFU.${NC}"
echo "AUTH_KEY: ${AUTH_KEY}"

# Generate a self-signed certificate if it doesn't exist
if [ ! -f nginx/ssl/fullchain.pem ] || [ ! -f nginx/ssl/privkey.pem ]; then
    echo -e "${YELLOW}No SSL certificates found. Generating self-signed certificate...${NC}"
    
    # Make the certificate generation script executable and run it
    chmod +x "$(dirname "$0")/generate-self-signed-cert.sh"
    ./generate-self-signed-cert.sh
fi

# Make the open-ports script executable
if [ -f "$(dirname "$0")/open-ports.sh" ]; then
    chmod +x "$(dirname "$0")/open-ports.sh"
fi

# Instructions for the user
echo -e "\n${GREEN}Setup complete!${NC}"
echo -e "To start the SFU server (from the docker directory):"
echo -e "  ${YELLOW}docker compose up -d${NC}"
echo -e "\nTo view logs:"
echo -e "  ${YELLOW}docker compose logs -f${NC}"
echo -e "\nTo stop the SFU server:"
echo -e "  ${YELLOW}docker compose down${NC}"
echo -e "\nThe SFU will be available at:"
echo -e "  HTTP:  http://${PUBLIC_IP}:${NGINX_HTTP_PORT:-80} (redirects to HTTPS)"
echo -e "  HTTPS: https://${PUBLIC_IP}:${NGINX_HTTPS_PORT:-443}"
echo -e "\nIn your Odoo instance, configure the following:"
echo -e "  RTC Server URL: https://${PUBLIC_IP}"
echo -e "  RTC Server KEY: ${AUTH_KEY}"
echo -e "\n${YELLOW}Important: Since you're using a self-signed certificate, browsers will show a security warning.${NC}"
echo -e "You'll need to accept the risk in your browser to access the SFU."
echo -e "\nOptionally, run the firewall configuration script to open required ports:"
echo -e "  ${YELLOW}sudo ./open-ports.sh${NC}"

chmod +x "$0"