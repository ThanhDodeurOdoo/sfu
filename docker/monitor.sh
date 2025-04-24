#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Odoo SFU Monitoring${NC}"

echo -e "\n${YELLOW}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E 'odoo-sfu|sfu-nginx'

echo -e "\n${YELLOW}Resource Usage:${NC}"
docker stats --no-stream odoo-sfu sfu-nginx

echo -e "\n${YELLOW}Recent Error Logs:${NC}"
docker logs --tail 100 odoo-sfu 2>&1 | grep -i "error\|exception" | tail -10
docker logs --tail 100 sfu-nginx 2>&1 | grep -i "error" | tail -10

echo -e "\n${YELLOW}Active Connections:${NC}"
docker exec sfu-nginx sh -c "nginx -T 2>/dev/null | grep -i 'connections'"

echo -e "\n${YELLOW}SFU Health Check:${NC}"
curl -s -o /dev/null -w "Status: %{http_code}\n" http://localhost:8070/v1/noop

echo -e "\n${YELLOW}SSL Certificate Information:${NC}"
if [ -f nginx/ssl/fullchain.pem ]; then
    CERT_END_DATE=$(openssl x509 -noout -in nginx/ssl/fullchain.pem -enddate | cut -d= -f2)
    CERT_END_EPOCH=$(date -d "${CERT_END_DATE}" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "${CERT_END_DATE}" +%s 2>/dev/null)
    CURRENT_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (CERT_END_EPOCH - CURRENT_EPOCH) / 86400 ))
    
    echo "Certificate expires on: ${CERT_END_DATE} (${DAYS_LEFT} days left)"
    
    if [ $DAYS_LEFT -lt 30 ]; then
        echo -e "${RED}WARNING: Certificate expires in less than 30 days!${NC}"
    fi
else
    echo "SSL certificate not found"
fi

echo -e "\n${YELLOW}Disk Space:${NC}"
df -h | grep -E "Filesystem|/$"

echo -e "\n${YELLOW}System Load:${NC}"
uptime

echo -e "\n${YELLOW}Memory Usage:${NC}"
free -h

echo -e "\n${YELLOW}Open RTC Ports:${NC}"
if command -v ss &>/dev/null; then
    ss -tuln | grep -E "40000|49999|8070|80|443"
elif command -v netstat &>/dev/null; then
    netstat -tuln | grep -E "40000|49999|8070|80|443"
else
    echo "No tool available to check ports (ss or netstat)"
fi

echo -e "\n${GREEN}Monitoring complete${NC}"