#!/bin/bash
# Simple script to generate Nginx configuration with the provided domain name

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain_name>"
    echo "Example: $0 tso-sfu-001.eu"
    exit 1
fi

# Create nginx conf.d directory if it doesn't exist
mkdir -p nginx/conf.d

# Generate the Nginx configuration
cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    # Redirect all HTTP traffic to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    # Enhanced security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    
    # Forward WebSocket connections to SFU
    location / {
        proxy_pass http://sfu:8070;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # Timeouts for long running WebSocket connections
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

echo "Nginx configuration for ${DOMAIN} generated successfully."