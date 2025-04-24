#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Odoo SFU Docker Setup Script${NC}"
echo "This script will help you set up the Odoo SFU in Docker."

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
    cat nginx/conf.d/default.conf > /dev/null 2>&1 || cp nginx-conf-template.conf nginx/conf.d/default.conf
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

# Function to validate domain name
validate_domain() {
    if [[ ! $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Ask about environment type
echo -e "\n${YELLOW}Choose your environment type:${NC}"
echo "1) Development/Testing (self-signed certificates)"
echo "2) Production (Let's Encrypt certificates)"
read -p "Enter choice [1-2] (default: 2): " ENV_TYPE
ENV_TYPE=${ENV_TYPE:-2}

if [ "$ENV_TYPE" = "1" ]; then
    ENVIRONMENT="development"
    USE_DOMAIN="false"
else
    ENVIRONMENT="production"
    USE_DOMAIN="true"
fi

echo "ENVIRONMENT=${ENVIRONMENT}" >> .env.new

# Get domain info if production
if [ "$USE_DOMAIN" = "true" ]; then
    read -p "Enter your domain name (e.g., sfu.example.com): " DOMAIN_NAME
    
    if [ -z "$DOMAIN_NAME" ]; then
        handle_error "Domain name is required for production setup."
    fi
    
    if ! validate_domain "$DOMAIN_NAME"; then
        handle_error "Invalid domain name format."
    fi
    
    echo "DOMAIN_NAME=${DOMAIN_NAME}" >> .env.new
    
    # Replace server_name in nginx config
    sed -i "s/server_name _;/server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};/g" nginx/conf.d/default.conf || echo "Warning: Could not update server_name in Nginx config"
fi

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
fi

echo "PUBLIC_IP=${PUBLIC_IP}" >> .env.new

# Generate AUTH_KEY if not exists
if [ -f .env ] && grep -q "AUTH_KEY" .env; then
    AUTH_KEY=$(grep AUTH_KEY .env | cut -d= -f2)
    echo -e "${YELLOW}Found existing AUTH_KEY.${NC}"
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
fi

echo "AUTH_KEY=${AUTH_KEY}" >> .env.new

# Determine number of CPU cores for NUM_WORKERS
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
RECOMMENDED_WORKERS=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
echo -e "${YELLOW}System has ${CPU_CORES} CPU cores. Recommended NUM_WORKERS: ${RECOMMENDED_WORKERS}${NC}"

# Calculate recommended resource limits
RECOMMENDED_CPU_LIMIT=$(echo "scale=1; ${CPU_CORES} * 0.8" | bc 2>/dev/null || echo "${CPU_CORES}")
RECOMMENDED_MEMORY=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.physmem 2>/dev/null | awk '{print $1/1024/1024}' || echo "1024")
RECOMMENDED_MEMORY_LIMIT=$(echo "${RECOMMENDED_MEMORY} * 0.7" | bc 2>/dev/null | cut -d. -f1 || echo "1024")

# Add optional configuration with defaults if not already in .env
if [ -f .env ]; then
    # Transfer any other existing settings not already handled
    grep -v "PUBLIC_IP\|AUTH_KEY\|NUM_WORKERS\|CPU_LIMIT\|MEMORY_LIMIT\|ENVIRONMENT\|DOMAIN_NAME" .env >> .env.new
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

# SSL Certificate handling
if [ "$USE_DOMAIN" = "true" ]; then
    # Check for existing Let's Encrypt certificates
    CERT_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}"
    
    if [ -d "$CERT_PATH" ]; then
        echo -e "${GREEN}Found Let's Encrypt certificates for ${DOMAIN_NAME}.${NC}"
        
        # Create symlinks to Let's Encrypt certificates
        if [ ! -f nginx/ssl/fullchain.pem ] || [ ! -f nginx/ssl/privkey.pem ]; then
            echo -e "${YELLOW}Creating symlinks to Let's Encrypt certificates...${NC}"
            ln -sf ${CERT_PATH}/fullchain.pem nginx/ssl/fullchain.pem
            ln -sf ${CERT_PATH}/privkey.pem nginx/ssl/privkey.pem
        fi
        
        # Set up renewal hook if it doesn't exist
        if [ ! -f /etc/letsencrypt/renewal-hooks/post/sfu-nginx-reload.sh ]; then
            echo -e "${YELLOW}Setting up certificate renewal hook...${NC}"
            
            mkdir -p /etc/letsencrypt/renewal-hooks/post
            cat > /etc/letsencrypt/renewal-hooks/post/sfu-nginx-reload.sh << EOL
#!/bin/bash
cp ${CERT_PATH}/fullchain.pem $(pwd)/nginx/ssl/fullchain.pem
cp ${CERT_PATH}/privkey.pem $(pwd)/nginx/ssl/privkey.pem
docker restart sfu-nginx
EOL
            chmod +x /etc/letsencrypt/renewal-hooks/post/sfu-nginx-reload.sh
        fi
    else
        echo -e "${YELLOW}No Let's Encrypt certificates found for ${DOMAIN_NAME}.${NC}"
        echo -e "You should obtain certificates using certbot:"
        echo -e "  sudo apt install certbot python3-certbot-nginx"
        echo -e "  sudo certbot --nginx -d ${DOMAIN_NAME} -d www.${DOMAIN_NAME}"
        
        echo -e "${YELLOW}Generating a temporary self-signed certificate until Let's Encrypt is set up...${NC}"
        
        # Generate temporary self-signed cert
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout nginx/ssl/privkey.pem \
            -out nginx/ssl/fullchain.pem \
            -subj "/CN=${DOMAIN_NAME}/O=Odoo SFU/C=US" \
            -addext "subjectAltName = DNS:${DOMAIN_NAME}, DNS:www.${DOMAIN_NAME}, IP:${PUBLIC_IP}"
    fi
else
    # Generate a self-signed certificate for development
    echo -e "${YELLOW}Generating self-signed certificate for development...${NC}"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout nginx/ssl/privkey.pem \
        -out nginx/ssl/fullchain.pem \
        -subj "/CN=${PUBLIC_IP}/O=Odoo SFU Dev/C=US" \
        -addext "subjectAltName = IP:${PUBLIC_IP}"
fi

# Make sure permissions are correct for SSL files
chmod 600 nginx/ssl/privkey.pem
chmod 644 nginx/ssl/fullchain.pem

./generate-nginx-conf.sh ${DOMAIN_NAME} ${PUBLIC_IP}

# Make the open-ports script executable if it exists
if [ -f open-ports.sh ]; then
    chmod +x open-ports.sh
fi

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
if [ "$USE_DOMAIN" = "true" ]; then
    echo -e "  HTTP:  http://${DOMAIN_NAME} (redirects to HTTPS)"
    echo -e "  HTTPS: https://${DOMAIN_NAME}"
    echo -e "\nIn your Odoo instance, configure the following:"
    echo -e "  RTC Server URL: https://${DOMAIN_NAME}"
    echo -e "  RTC Server KEY: ${AUTH_KEY}"
    
    if [ ! -d "$CERT_PATH" ]; then
        echo -e "\n${YELLOW}Remember to set up Let's Encrypt certificates!${NC}"
    fi
else
    echo -e "  HTTP:  http://${PUBLIC_IP} (redirects to HTTPS)"
    echo -e "  HTTPS: https://${PUBLIC_IP}"
    echo -e "\nIn your Odoo instance, configure the following:"
    echo -e "  RTC Server URL: https://${PUBLIC_IP}"
    echo -e "  RTC Server KEY: ${AUTH_KEY}"
    echo -e "\n${YELLOW}Note: Since you're using a self-signed certificate, browsers will show a security warning.${NC}"
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