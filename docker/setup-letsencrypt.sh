#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}This script must be run as root (use sudo)${NC}"
  exit 1
fi

echo -e "${GREEN}Let's Encrypt Certificate Setup for Odoo SFU${NC}"

# Stop containers if they're running
echo -e "${YELLOW}Stopping running containers...${NC}"
docker compose down 2>/dev/null || true

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Check for domain name
if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${YELLOW}No domain name found in .env. Please enter your domain name:${NC}"
    read -p "Domain name: " DOMAIN_NAME
    
    if [ -z "$DOMAIN_NAME" ]; then
        echo -e "${RED}Error: Domain name is required${NC}"
        exit 1
    fi
    
    # Add to .env if it doesn't exist
    if ! grep -q "DOMAIN_NAME" .env; then
        echo "DOMAIN_NAME=${DOMAIN_NAME}" >> .env
    else
        sed -i "s/DOMAIN_NAME=.*/DOMAIN_NAME=${DOMAIN_NAME}/" .env
    fi
fi

# Install Certbot and Nginx plugin
echo -e "${YELLOW}Installing Certbot...${NC}"
apt update
apt install -y certbot python3-certbot-nginx

# Check if port 80 is available
if netstat -tuln | grep -q ":80 "; then
    echo -e "${YELLOW}Port 80 is in use. Stopping services to free up the port...${NC}"
    systemctl stop nginx 2>/dev/null || true
    lsof -ti:80 | xargs kill -9 2>/dev/null || true
fi

# Obtain certificates
echo -e "${YELLOW}Obtaining Let's Encrypt certificates for ${DOMAIN_NAME}...${NC}"
certbot certonly --standalone --preferred-challenges http -d ${DOMAIN_NAME} -d www.${DOMAIN_NAME}

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to obtain certificates. Check your domain configuration.${NC}"
    exit 1
fi

# Copy certificates to nginx/ssl directory
echo -e "${YELLOW}Copying certificates to Nginx directory...${NC}"
mkdir -p nginx/ssl
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem nginx/ssl/
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem nginx/ssl/

# Set proper permissions
chmod 644 nginx/ssl/fullchain.pem
chmod 600 nginx/ssl/privkey.pem

# Create renewal hook
echo -e "${YELLOW}Setting up certificate renewal hook...${NC}"
mkdir -p /etc/letsencrypt/renewal-hooks/post

cat > /etc/letsencrypt/renewal-hooks/post/sfu-nginx-reload.sh << EOF
#!/bin/bash
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem $(pwd)/nginx/ssl/fullchain.pem
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem $(pwd)/nginx/ssl/privkey.pem
docker restart sfu-nginx
EOF

chmod +x /etc/letsencrypt/renewal-hooks/post/sfu-nginx-reload.sh

# Update Nginx configuration
echo -e "${YELLOW}Updating Nginx configuration...${NC}"
sed -i "s/server_name _;/server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};/g" nginx/conf.d/default.conf

# Start containers
echo -e "${YELLOW}Starting containers...${NC}"
docker compose up -d

# Test renewal
echo -e "${YELLOW}Testing certificate renewal...${NC}"
certbot renew --dry-run

echo -e "${GREEN}Let's Encrypt certificate setup complete!${NC}"
echo -e "Your certificates are installed and will auto-renew."
echo -e "Your SFU should now be accessible at: https://${DOMAIN_NAME}"
echo -e "\nIn your Odoo instance, configure the following:"
echo -e "  RTC Server URL: https://${DOMAIN_NAME}"
echo -e "  RTC Server KEY: ${AUTH_KEY}"

# Add cron job for certificate verification
echo -e "${YELLOW}Adding regular certificate verification check...${NC}"
(crontab -l 2>/dev/null || echo "") | grep -v "certbot renew" | { cat; echo "0 2 * * * certbot renew --quiet"; } | crontab -