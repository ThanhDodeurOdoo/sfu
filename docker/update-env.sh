#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Odoo SFU Environment Updater${NC}"

# Set the directory to docker folder
cd "$(dirname "$0")"

# Error handling function
handle_error() {
    echo -e "${RED}Error: ${1}${NC}"
    exit 1
}

# Check if .env exists
if [ ! -f .env ]; then
    handle_error "No .env file found. Please run setup.sh first."
fi

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  ./update-env.sh KEY1=VALUE1 KEY2=VALUE2 ..."
    echo -e "\n${YELLOW}Examples:${NC}"
    echo -e "  ./update-env.sh LOG_LEVEL=debug AUTH_KEY=abc123"
    echo -e "  ./update-env.sh CHANNEL_SIZE=200 MAX_BITRATE_IN=10000000"
    echo -e "\n${YELLOW}Current .env contents:${NC}"
    grep -v "^#" .env | grep -v "^$" | sort
    exit 0
fi

# Create a temporary file
TEMP_ENV=$(mktemp)

# Copy the current .env file to the temporary file
cp .env $TEMP_ENV

# Process each key-value pair
UPDATED_KEYS=()
for arg in "$@"; do
    # Check if argument has the correct format
    if [[ ! "$arg" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        handle_error "Invalid format for '$arg'. Must be KEY=VALUE"
    fi

    # Extract key and value
    KEY=$(echo $arg | cut -d= -f1)
    VALUE=$(echo $arg | cut -d= -f2-)

    # Check if the key already exists in the .env file
    if grep -q "^${KEY}=" $TEMP_ENV; then
        # Update the existing key
        sed -i.bak "s|^${KEY}=.*|${KEY}=${VALUE}|" $TEMP_ENV
    else
        # Add the new key-value pair
        echo "${KEY}=${VALUE}" >> $TEMP_ENV
    fi

    UPDATED_KEYS+=("$KEY")
done

# Replace the original .env with the updated one
mv $TEMP_ENV .env

# Make sure permissions are correct
chmod 600 .env

echo -e "${GREEN}Environment updated successfully!${NC}"
echo -e "${YELLOW}Updated keys:${NC}"
for key in "${UPDATED_KEYS[@]}"; do
    value=$(grep "^${key}=" .env | cut -d= -f2-)
    echo -e "  ${key}=${value}"
done

# Inform about service restart if needed
echo -e "\n${YELLOW}Note:${NC} Some changes may require restarting the SFU to take effect:"
echo -e "  ${GREEN}docker compose down${NC}"
echo -e "  ${GREEN}docker compose up -d${NC}"

# Check if any critical keys were updated
CRITICAL_KEYS=("PUBLIC_IP" "AUTH_KEY" "RTC_MIN_PORT" "RTC_MAX_PORT" "NUM_WORKERS")
RESTART_NEEDED=false

for key in "${UPDATED_KEYS[@]}"; do
    if [[ " ${CRITICAL_KEYS[@]} " =~ " ${key} " ]]; then
        RESTART_NEEDED=true
        break
    fi
done

if [ "$RESTART_NEEDED" = true ]; then
    echo -e "\n${RED}Critical configuration has been changed!${NC}"
    echo -e "${YELLOW}You MUST restart the SFU for these changes to take effect.${NC}"
fi
