#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Generating Self-Signed SSL Certificate${NC}"

cd "$(dirname "$0")"
mkdir -p nginx/ssl
if [ -f .env ]; then
    source .env
fi

if [ -z "$PUBLIC_IP" ] && [ -f .env ]; then
    PUBLIC_IP=$(grep PUBLIC_IP .env | cut -d= -f2)
fi

if [ -z "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}Could not find PUBLIC_IP in .env file. Please enter your server's public IP:${NC}"
    read -p "Public IP: " PUBLIC_IP
fi

echo -e "${YELLOW}Generating self-signed certificate for IP: ${PUBLIC_IP}${NC}"

cat > nginx/ssl/openssl.cnf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = Belgium
ST = Brabant-Wallon
L = Unknown
O = TSO-TESTING
OU = Organizational Unit
CN = ${PUBLIC_IP}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
IP.1 = ${PUBLIC_IP}
EOF

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout nginx/ssl/privkey.pem \
    -out nginx/ssl/fullchain.pem \
    -config nginx/ssl/openssl.cnf

chmod 600 nginx/ssl/privkey.pem
chmod 644 nginx/ssl/fullchain.pem

echo -e "${GREEN}Self-signed certificate generated successfully!${NC}"
echo -e "${YELLOW}Note: Browsers will show a security warning when accessing this site because it uses a self-signed certificate.${NC}"
echo -e "${YELLOW}For production use, consider obtaining a proper SSL certificate from a Certificate Authority or using a domain name with Let's Encrypt.${NC}"