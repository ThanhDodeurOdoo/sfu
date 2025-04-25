#!/bin/bash
# Enhanced script to generate secure Nginx configuration with the provided domain name and IP

DOMAIN=$1
IP=$2

if [ -z "$DOMAIN" ] || [ -z "$IP" ]; then
    echo "Usage: $0 <domain_name> <server_ip>"
    echo "Example: $0 tso-sfu-001.eu 51.91.249.43"
    
    # Try to get values from .env if not provided
    if [ -f .env ]; then
        source .env
        DOMAIN=${DOMAIN_NAME}
        IP=${PUBLIC_IP}
        
        if [ -n "$DOMAIN" ] && [ -n "$IP" ]; then
            echo "Found domain ($DOMAIN) and IP ($IP) from .env file. Continuing..."
        else
            exit 1
        fi
    else
        exit 1
    fi
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

# Block direct IP access
server {
    listen 80;
    listen 443 ssl;
    server_name ${IP};
    
    # SSL configuration if accessed directly via IP (for rejection)
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    return 444;  # Connection closed without response
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    # Enhanced SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; connect-src 'self' wss://\$host; upgrade-insecure-requests;";
    
    # Hide server information
    server_tokens off;
    
    # Request size limits
    client_max_body_size 1m;
    client_body_timeout 10s;
    client_header_timeout 10s;
    
    # Define rate limiting zones
    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;
    
    # Forward traffic to SFU
    location / {
        proxy_pass http://localhost:8070;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # Apply rate limiting
        limit_req zone=api_limit burst=20 nodelay;
        limit_conn conn_limit 10;
        
        # Timeouts for WebSocket connections
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
    
    # Stats endpoint with basic auth (uncomment and configure if needed)
    #location /v1/stats {
    #    auth_basic "Restricted Access";
    #    auth_basic_user_file /etc/nginx/.htpasswd;
    #    
    #    proxy_pass http://localhost:8070;
    #    proxy_http_version 1.1;
    #    proxy_set_header Host \$host;
    #    proxy_set_header X-Real-IP \$remote_addr;
    #    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    #    proxy_set_header X-Forwarded-Proto \$scheme;
    #}
    
    # Deny access to hidden files
    location ~ /\\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

echo "Secure Nginx configuration for ${DOMAIN} generated successfully."
echo "Key security features added:"
echo " - TLS hardening"
echo " - HTTP security headers"
echo " - Rate limiting"
echo " - Direct IP access blocking"
echo " - Request size limits"
echo " - Server information hiding"

# Provide information about enabling basic auth if needed
echo ""
echo "To enable basic authentication for admin endpoints:"
echo "1. Install apache2-utils: sudo apt install apache2-utils"
echo "2. Create password file: sudo htpasswd -c /etc/nginx/.htpasswd admin"
echo "3. Uncomment the /v1/stats location block in the configuration"
