#!/bin/bash
# Backup script for Odoo SFU

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Create backup directory if it doesn't exist
BACKUP_DIR=${BACKUP_DIR:-/var/backups/odoo-sfu}
mkdir -p $BACKUP_DIR || { echo -e "${RED}Failed to create backup directory${NC}"; exit 1; }

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="odoo-sfu-backup-${TIMESTAMP}"
BACKUP_TEMP_DIR="/tmp/${BACKUP_NAME}"
mkdir -p $BACKUP_TEMP_DIR

echo -e "${GREEN}Starting Odoo SFU backup...${NC}"

# Backup the .env file
echo -e "${YELLOW}Backing up .env file...${NC}"
cp .env ${BACKUP_TEMP_DIR}/env.txt || { echo -e "${RED}Failed to backup .env file${NC}"; }

# Backup SSL certificates
echo -e "${YELLOW}Backing up SSL certificates...${NC}"
if [ -d nginx/ssl ]; then
    mkdir -p ${BACKUP_TEMP_DIR}/nginx/ssl
    cp -r nginx/ssl/* ${BACKUP_TEMP_DIR}/nginx/ssl/ || { echo -e "${RED}Failed to backup SSL certificates${NC}"; }
else
    echo -e "${YELLOW}SSL directory not found, skipping${NC}"
fi

# Backup nginx configuration
echo -e "${YELLOW}Backing up Nginx configuration...${NC}"
if [ -d nginx/conf.d ]; then
    mkdir -p ${BACKUP_TEMP_DIR}/nginx/conf.d
    cp -r nginx/conf.d/* ${BACKUP_TEMP_DIR}/nginx/conf.d/ || { echo -e "${RED}Failed to backup Nginx configuration${NC}"; }
else
    echo -e "${YELLOW}Nginx conf directory not found, skipping${NC}"
fi

# Backup docker-compose file
echo -e "${YELLOW}Backing up docker-compose.yml...${NC}"
if [ -f docker-compose.yml ]; then
    cp docker-compose.yml ${BACKUP_TEMP_DIR}/ || { echo -e "${RED}Failed to backup docker-compose.yml${NC}"; }
else
    echo -e "${YELLOW}docker-compose.yml not found, skipping${NC}"
fi

# Create archive
echo -e "${YELLOW}Creating archive...${NC}"
tar -czf ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz -C /tmp ${BACKUP_NAME} || { 
    echo -e "${RED}Failed to create backup archive${NC}"; 
    rm -rf ${BACKUP_TEMP_DIR}
    exit 1; 
}

# Cleanup temp directory
rm -rf ${BACKUP_TEMP_DIR}

# Keep only the last 7 backups
echo -e "${YELLOW}Cleaning up old backups, keeping the latest 7...${NC}"
ls -t ${BACKUP_DIR}/odoo-sfu-backup-*.tar.gz | tail -n +8 | xargs -r rm

# List current backups
echo -e "${YELLOW}Current backups:${NC}"
ls -lh ${BACKUP_DIR}/odoo-sfu-backup-*.tar.gz | sort -r

echo -e "${GREEN}Backup completed to ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz${NC}"

# Optional: Add a reminder for offsite backup
echo -e "${YELLOW}Remember to periodically copy your backups to an offsite location:${NC}"
echo "scp ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz user@offsite-server:/path/to/backups/"