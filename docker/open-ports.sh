#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Opening required ports for Odoo SFU on OVH VPS${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}This script must be run as root (use sudo)${NC}"
  exit 1
fi

if ! command -v ufw &> /dev/null; then
    echo -e "${YELLOW}UFW firewall not found. Installing...${NC}"
    apt-get update
    apt-get install -y ufw
fi

if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

HTTP_PORT=${NGINX_HTTP_PORT:-80}
HTTPS_PORT=${NGINX_HTTPS_PORT:-443}
SFU_PORT=${PORT:-8070}
RTC_MIN=${RTC_MIN_PORT:-40000}
RTC_MAX=${RTC_MAX_PORT:-49999}

echo -e "${YELLOW}Configuring firewall rules...${NC}"

echo -e "- Allowing SSH connections"
ufw allow ssh

echo -e "- Allowing HTTP port $HTTP_PORT"
ufw allow $HTTP_PORT/tcp
echo -e "- Allowing HTTPS port $HTTPS_PORT"
ufw allow $HTTPS_PORT/tcp

echo -e "- Allowing SFU port $SFU_PORT"
ufw allow $SFU_PORT/tcp

echo -e "- Allowing RTC TCP ports $RTC_MIN-$RTC_MAX"
ufw allow $RTC_MIN:$RTC_MAX/tcp
echo -e "- Allowing RTC UDP ports $RTC_MIN-$RTC_MAX"
ufw allow $RTC_MIN:$RTC_MAX/udp

if ! ufw status | grep -q "Status: active"; then
    echo -e "${YELLOW}Enabling UFW firewall...${NC}"
    ufw --force enable
fi

echo -e "${GREEN}Firewall configuration complete!${NC}"
echo -e "Current UFW status:"
ufw status verbose

echo -e "\n${YELLOW}OVH VPS Specific Instructions:${NC}"
echo -e "1. In addition to the local firewall configured above, you need to check OVH's network firewall:"
echo -e "   - Log in to OVH Control Panel (https://www.ovh.com/manager/)"
echo -e "   - Navigate to your VPS"
echo -e "   - Go to 'Network' tab"
echo -e "   - Verify that the following ports are open:"
echo -e "     * 22/TCP (SSH)"
echo -e "     * 80/TCP (HTTP)"
echo -e "     * 443/TCP (HTTPS)"
echo -e "     * 8070/TCP (SFU)"
echo -e "     * ${RTC_MIN}-${RTC_MAX}/TCP (RTC)"
echo -e "     * ${RTC_MIN}-${RTC_MAX}/UDP (RTC)"
echo -e "2. If using IPv6, ensure IPv6 connectivity works:"
echo -e "   ip -6 addr show"
echo -e "3. Test UDP connectivity which is essential for WebRTC:"
echo -e "   sudo apt install -y netcat"
echo -e "   nc -l -u -p 40500 &  # This starts a UDP listener"
echo -e "   nc -z -u -v localhost 40500  # This tests UDP connection"
echo -e "4. UDP Rate limiting: OVH may have UDP rate limiting which can affect WebRTC."
echo -e "   Contact OVH support if you experience connection issues."