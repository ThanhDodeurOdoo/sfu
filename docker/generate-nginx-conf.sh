#!/bin/bash
# Script to generate secure Nginx configuration with the provided domain name and IP

DOMAIN=$1
IP=$2

if [ -z "$DOMAIN" ] || [ -z "$IP" ]; then
    echo "Usage: $0 <domain_name> <server_ip>"
    echo "Example: $0 odoo-sfu-006.eu 55.81.244.42"
    
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

# Generate a random password for stats access if not specified
STATS_USERNAME="admin"
STATS_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)

# Create nginx conf.d directory if it doesn't exist
mkdir -p nginx/conf.d

# Create the main nginx.conf for the http context
cat > nginx/conf.d/http-context.conf << EOF
# Define rate limiting zones - must be in http context
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;
EOF

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
    add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline' fonts.googleapis.com; script-src 'self' 'unsafe-inline'; font-src 'self' fonts.gstatic.com; connect-src 'self' wss://\$host; upgrade-insecure-requests;";

    # Hide server information
    server_tokens off;

    # Request size limits
    client_max_body_size 1m;
    client_body_timeout 10s;
    client_header_timeout 10s;

    # SFU Monitor Dashboard (protected)
    location /monitor {
        auth_basic "SFU Monitor Access";
        auth_basic_user_file /etc/nginx/stats_auth;

        # Remove /monitor prefix when proxying
        rewrite ^/monitor/?(.*) /\$1 break;

        proxy_pass http://localhost:8071;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Enable WebSocket support if needed
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    # API endpoints for monitor (also protected)
    location ~ ^/monitor-api/(logs|health) {
        auth_basic "SFU Monitor API";
        auth_basic_user_file /etc/nginx/stats_auth;

        # Remove /monitor-api prefix when proxying
        rewrite ^/monitor-api/(.*) /\$1 break;

        proxy_pass http://localhost:8071;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Restrict access to stats endpoints with generated credentials
    location ~ /v1/stats {
        auth_basic "SFU Statistics Access";
        auth_basic_user_file /etc/nginx/stats_auth;

        proxy_pass http://localhost:8070;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Allow noop endpoint without auth (for health checks)
    location /v1/noop {
        proxy_pass http://localhost:8070;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Forward traffic to SFU for all other routes
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

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Block access to sensitive non-hidden paths
    location ~ ^/(ssl|etc|nginx/ssl|docker|backup|private|certs) {
        deny all;
        return 404;
        access_log off;
        log_not_found off;
    }
}
EOF

mkdir -p nginx/ssl
PASSWORD_HASH=$(openssl passwd -apr1 "$STATS_PASSWORD")
echo "${STATS_USERNAME}:${PASSWORD_HASH}" > nginx/ssl/stats_auth

# Set proper permissions
chmod 644 nginx/ssl/stats_auth

echo "Secure Nginx configuration for ${DOMAIN} generated successfully."
echo ""
echo "Stats access credentials:"
echo " - Username: ${STATS_USERNAME}"
echo " - Password: ${STATS_PASSWORD}"
echo ""
