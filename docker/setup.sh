#!/bin/bash
set -e

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Odoo SFU Docker Setup Script${NC}"
echo "This script will help you set up the Odoo SFU in Docker."

# Error handling function
handle_error() {
    echo -e "${RED}Error: ${1}${NC}"
    exit 1
}

# Set the directory to docker folder
cd "$(dirname "$0")"

# Create necessary directories
mkdir -p nginx/conf.d nginx/ssl

# Check if default.conf already exists, create if not
if [ ! -f nginx/conf.d/default.conf ]; then
    echo -e "${YELLOW}Creating Nginx configuration...${NC}"
    cat > nginx/conf.d/default.conf << 'EOF'
# Rate limiting zone
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

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
    
    # Enhanced security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # HSTS (optional, comment if causing issues)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Additional security headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    
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
    
    # Apply rate limiting only to API endpoints
    location ~ ^/v[0-9]+/ {
        proxy_pass http://sfu:8070;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # Rate limiting
        limit_req zone=api burst=20 nodelay;
    }
    
    # Health check endpoint without rate limiting
    location = /v1/noop {
        proxy_pass http://sfu:8070;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    echo -e "${GREEN}Nginx configuration created.${NC}"
fi

# Initialize .env file if it doesn't exist
touch .env.new

# Function to validate IP address
validate_ip() {
    if [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    return 0
}

# Get public IP if not already known
if [ -f .env ] && grep -q "PUBLIC_IP" .env; then
    PUBLIC_IP=$(grep PUBLIC_IP .env | cut -d= -f2)
    echo -e "${YELLOW}Found existing PUBLIC_IP: ${PUBLIC_IP}${NC}"
    
    # Validate the found IP
    if ! validate_ip "$PUBLIC_IP"; then
        echo -e "${RED}Invalid IP format found in .env. Detecting new IP...${NC}"
        PUBLIC_IP=""
    fi
fi

if [ -z "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}Detecting public IP address...${NC}"
    # Try multiple services for redundancy
    PUBLIC_IP=$(curl -s https://ipinfo.io/ip || curl -s https://api.ipify.org || curl -s https://icanhazip.com)
    
    if [ -z "$PUBLIC_IP" ]; then
        echo -e "${YELLOW}Could not auto-detect public IP. Please enter it manually:${NC}"
        read -p "Public IP: " PUBLIC_IP
        
        # Validate the manual IP
        if ! validate_ip "$PUBLIC_IP"; then
            handle_error "Invalid IP format. Please run the script again and provide a valid IP address."
        fi
    else
        echo -e "${GREEN}Detected public IP: ${PUBLIC_IP}${NC}"
    fi
    echo "PUBLIC_IP=${PUBLIC_IP}" >> .env.new
else
    echo "PUBLIC_IP=${PUBLIC_IP}" >> .env.new
fi

# Generate AUTH_KEY if not exists
if [ -f .env ] && grep -q "AUTH_KEY" .env; then
    AUTH_KEY=$(grep AUTH_KEY .env | cut -d= -f2)
    echo -e "${YELLOW}Found existing AUTH_KEY.${NC}"
    echo "AUTH_KEY=${AUTH_KEY}" >> .env.new
else
    echo -e "${YELLOW}Generating new AUTH_KEY...${NC}"
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        handle_error "OpenSSL is not installed. Please install it and try again."
    fi
    
    AUTH_KEY=$(openssl rand -base64 32)
    if [ -z "$AUTH_KEY" ]; then
        handle_error "Failed to generate AUTH_KEY."
    fi
    
    echo -e "${GREEN}Generated new AUTH_KEY.${NC}"
    echo "AUTH_KEY=${AUTH_KEY}" >> .env.new
fi

# Determine number of CPU cores for NUM_WORKERS
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
RECOMMENDED_WORKERS=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
echo -e "${YELLOW}System has ${CPU_CORES} CPU cores. Recommended NUM_WORKERS: ${RECOMMENDED_WORKERS}${NC}"

# Calculate recommended resource limits
RECOMMENDED_CPU_LIMIT=$(echo "scale=1; ${CPU_CORES} * 0.8" | bc 2>/dev/null || echo "${CPU_CORES}")
RECOMMENDED_MEMORY=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "1024")
RECOMMENDED_MEMORY_LIMIT=$(echo "${RECOMMENDED_MEMORY} * 0.7" | bc 2>/dev/null | cut -d. -f1 || echo "1024")

# Ask about environment type
echo -e "\n${YELLOW}Choose your environment type:${NC}"
echo "1) Development/Testing (self-signed certificates)"
echo "2) Production (Let's Encrypt certificates)"
read -p "Enter choice [1-2] (default: 1): " ENV_TYPE
ENV_TYPE=${ENV_TYPE:-1}

if [ "$ENV_TYPE" = "1" ]; then
    ENVIRONMENT="development"
else
    ENVIRONMENT="production"
fi

# Add optional configuration with defaults if not already in .env
if [ -f .env ]; then
    # Transfer any other existing settings not already handled
    grep -v "PUBLIC_IP\|AUTH_KEY\|NUM_WORKERS\|CPU_LIMIT\|MEMORY_LIMIT\|ENVIRONMENT" .env >> .env.new
fi

# Add default values if not already set
cat >> .env.new << EOF
# Environment type
ENVIRONMENT=${ENVIRONMENT}

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

# Resource limits
CPU_LIMIT=${RECOMMENDED_CPU_LIMIT}
MEMORY_LIMIT=${RECOMMENDED_MEMORY_LIMIT}M

# Logging settings
LOG_LEVEL=info
LOG_TIMESTAMP=true
LOG_COLOR=true

# Nginx port settings
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443

# Use HTTPS
USE_HTTPS=true

# Backup directory
BACKUP_DIR=/var/backups/odoo-sfu
EOF

# Replace old .env with new one
mv .env.new .env

echo -e "${GREEN}Configuration saved to .env file.${NC}"
echo -e "${YELLOW}Important: Keep your AUTH_KEY secure - you'll need it to connect Odoo to this SFU.${NC}"
echo "AUTH_KEY: ${AUTH_KEY}"

if [ "$ENV_TYPE" = "1" ]; then
    # Generate a self-signed certificate if it doesn't exist
    if [ ! -f nginx/ssl/fullchain.pem ] || [ ! -f nginx/ssl/privkey.pem ]; then
        echo -e "${YELLOW}No SSL certificates found. Generating self-signed certificate...${NC}"
        
        # Make the certificate generation script executable and run it
        chmod +x "$(dirname "$0")/generate-self-signed-cert.sh"
        ./generate-self-signed-cert.sh || handle_error "Failed to generate SSL certificate."
    fi
else
    echo -e "${YELLOW}For production environments, we recommend using Let's Encrypt for valid SSL certificates.${NC}"
    echo -e "You will need a domain name pointing to this server."
    
    read -p "Enter your domain name (e.g., sfu.example.com): " DOMAIN_NAME
    
    if [ -z "$DOMAIN_NAME" ]; then
        handle_error "Domain name is required for Let's Encrypt setup."
    fi
    
    echo "DOMAIN_NAME=${DOMAIN_NAME}" >> .env
    
    echo -e "${YELLOW}Setting up Let's Encrypt:${NC}"
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        echo -e "Certbot not found. Instructions to install:"
        echo -e "  1. Install certbot: sudo apt-get update && sudo apt-get install certbot python3-certbot-nginx"
        echo -e "  2. Get certificate: sudo certbot --nginx -d ${DOMAIN_NAME}"
    else
        echo -e "Certbot is installed. Run the following to get your certificate:"
        echo -e "  sudo certbot --nginx -d ${DOMAIN_NAME}"
    fi
    
    # Generate temporary self-signed cert anyway
    echo -e "${YELLOW}Generating a temporary self-signed certificate until Let's Encrypt is set up...${NC}"
    chmod +x "$(dirname "$0")/generate-self-signed-cert.sh"
    ./generate-self-signed-cert.sh || handle_error "Failed to generate temporary SSL certificate."
fi

# Make the open-ports script executable
if [ -f "$(dirname "$0")/open-ports.sh" ]; then
    chmod +x "$(dirname "$0")/open-ports.sh"
fi

# Create a backup script
cat > backup.sh << 'EOF'
#!/bin/bash
# Backup script for Odoo SFU

# Load environment variables
source .env

# Create backup directory if it doesn't exist
BACKUP_DIR=${BACKUP_DIR:-/var/backups/odoo-sfu}
mkdir -p $BACKUP_DIR

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup the .env file
cp .env ${BACKUP_DIR}/env_backup_${TIMESTAMP}.txt

# Backup SSL certificates
tar -czf ${BACKUP_DIR}/ssl_backup_${TIMESTAMP}.tar.gz nginx/ssl

# Backup nginx configuration
tar -czf ${BACKUP_DIR}/nginx_conf_backup_${TIMESTAMP}.tar.gz nginx/conf.d

# Backup complete
echo "Backup completed to ${BACKUP_DIR}"
EOF

chmod +x backup.sh

# Create a monitoring script
cat > monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script for Odoo SFU

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Odoo SFU Monitoring${NC}"

# Check container status
echo -e "\n${YELLOW}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E 'odoo-sfu|sfu-nginx'

# Check container resource usage
echo -e "\n${YELLOW}Resource Usage:${NC}"
docker stats --no-stream odoo-sfu sfu-nginx

# Check logs for errors (last 10 error lines)
echo -e "\n${YELLOW}Recent Error Logs:${NC}"
docker logs --tail 100 odoo-sfu 2>&1 | grep -i "error\|exception" | tail -10
docker logs --tail 100 sfu-nginx 2>&1 | grep -i "error" | tail -10

# Check SFU endpoint
echo -e "\n${YELLOW}SFU Health Check:${NC}"
curl -s -o /dev/null -w "Status: %{http_code}\n" http://localhost:8070/v1/noop

# Check SSL certificate expiration
echo -e "\n${YELLOW}SSL Certificate Information:${NC}"
if [ -f nginx/ssl/fullchain.pem ]; then
    openssl x509 -noout -in nginx/ssl/fullchain.pem -dates
else
    echo "SSL certificate not found"
fi
EOF

chmod +x monitor.sh

# Instructions for the user
echo -e "\n${GREEN}Setup complete!${NC}"
echo -e "To start the SFU server (from the docker directory):"
echo -e "  ${YELLOW}docker compose up -d${NC}"
echo -e "\nTo view logs:"
echo -e "  ${YELLOW}docker compose logs -f${NC}"
echo -e "\nTo stop the SFU server:"
echo -e "  ${YELLOW}docker compose down${NC}"
echo -e "\nTo make a backup of your configuration:"
echo -e "  ${YELLOW}./backup.sh${NC}"
echo -e "\nTo monitor your SFU deployment:"
echo -e "  ${YELLOW}./monitor.sh${NC}"

echo -e "\nThe SFU will be available at:"
if [ "$ENV_TYPE" = "1" ]; then
    echo -e "  HTTP:  http://${PUBLIC_IP}:${NGINX_HTTP_PORT:-80} (redirects to HTTPS)"
    echo -e "  HTTPS: https://${PUBLIC_IP}:${NGINX_HTTPS_PORT:-443}"
    echo -e "\nIn your Odoo instance, configure the following:"
    echo -e "  RTC Server URL: https://${PUBLIC_IP}"
    echo -e "  RTC Server KEY: ${AUTH_KEY}"
    echo -e "\n${YELLOW}Important: Since you're using a self-signed certificate, browsers will show a security warning.${NC}"
    echo -e "You'll need to accept the risk in your browser to access the SFU."
else
    echo -e "  HTTP:  http://${DOMAIN_NAME}:${NGINX_HTTP_PORT:-80} (redirects to HTTPS)"
    echo -e "  HTTPS: https://${DOMAIN_NAME}:${NGINX_HTTPS_PORT:-443}"
    echo -e "\nIn your Odoo instance, configure the following:"
    echo -e "  RTC Server URL: https://${DOMAIN_NAME}"
    echo -e "  RTC Server KEY: ${AUTH_KEY}"
    echo -e "\n${YELLOW}Remember to set up Let's Encrypt as described above.${NC}"
fi

echo -e "\nOptionally, run the firewall configuration script to open required ports:"
echo -e "  ${YELLOW}sudo ./open-ports.sh${NC}"

# Add periodic backup and monitoring reminder
echo -e "\n${YELLOW}Recommendation: Set up cron jobs for periodic backups and monitoring:${NC}"
echo -e "Run 'crontab -e' and add the following lines:"
echo -e "  # Daily backup at 3 AM"
echo -e "  0 3 * * * cd $(pwd) && ./backup.sh"
echo -e "  # Monitoring check every 15 minutes"
echo -e "  */15 * * * * cd $(pwd) && ./monitor.sh > /var/log/sfu-monitor.log 2>&1"

chmod +x "$0"