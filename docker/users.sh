#!/bin/bash

# Script to manage stats authentication users
# This script can be run by the ubuntu user without sudo
# Uses only built-in tools - no apache2-utils dependency required

STATS_AUTH_FILE="/opt/sfu/docker/nginx/ssl/stats_auth"

# Function to display usage
usage() {
    echo "Usage: $0 [add|remove|list] [username]"
    echo ""
    echo "Commands:"
    echo "  add <username>     - Add or update a user (will prompt for password)"
    echo "  remove <username>  - Remove a user"
    echo "  list              - List all users"
    echo ""
    echo "Examples:"
    echo "  $0 add admin"
    echo "  $0 remove olduser"
    echo "  $0 list"
}

# Function to generate password hash using openssl
generate_hash() {
    local password=$1
    openssl passwd -apr1 "$password"
}

# Function to add/update user
add_user() {
    local username=$1
    if [ -z "$username" ]; then
        echo "❌ Error: Username is required"
        usage
        exit 1
    fi

    # Validate username (no colons or spaces)
    if [[ "$username" == *":"* ]] || [[ "$username" == *" "* ]]; then
        echo "❌ Error: Username cannot contain colons or spaces"
        exit 1
    fi

    # Create directory if it doesn't exist
    mkdir -p $(dirname "$STATS_AUTH_FILE")

    # Prompt for password
    echo -n "Enter password for user '$username': "
    read -s password
    echo
    echo -n "Confirm password: "
    read -s password_confirm
    echo

    if [ "$password" != "$password_confirm" ]; then
        echo "❌ Error: Passwords do not match"
        exit 1
    fi

    if [ -z "$password" ]; then
        echo "❌ Error: Password cannot be empty"
        exit 1
    fi

    # Generate password hash
    local hash=$(generate_hash "$password")
    local auth_line="$username:$hash"

    # Create temp file for atomic update
    local temp_file="${STATS_AUTH_FILE}.tmp"

    # If file exists, remove existing user and add new entry
    if [ -f "$STATS_AUTH_FILE" ]; then
        grep -v "^$username:" "$STATS_AUTH_FILE" > "$temp_file" 2>/dev/null || true
    else
        touch "$temp_file"
    fi

    # Add the new user
    echo "$auth_line" >> "$temp_file"

    # Atomic move
    mv "$temp_file" "$STATS_AUTH_FILE"

    # Set correct permissions
    chmod 644 "$STATS_AUTH_FILE"

    echo "✅ User '$username' added/updated successfully"
    echo "📁 File location: $STATS_AUTH_FILE"
}

# Function to remove user
remove_user() {
    local username=$1
    if [ -z "$username" ]; then
        echo "❌ Error: Username is required"
        usage
        exit 1
    fi

    if [ ! -f "$STATS_AUTH_FILE" ]; then
        echo "❌ Error: Stats auth file not found at $STATS_AUTH_FILE"
        exit 1
    fi

    # Check if user exists
    if ! grep -q "^$username:" "$STATS_AUTH_FILE"; then
        echo "❌ Error: User '$username' not found"
        exit 1
    fi

    # Create temp file without the user
    local temp_file="${STATS_AUTH_FILE}.tmp"
    grep -v "^$username:" "$STATS_AUTH_FILE" > "$temp_file"

    # Atomic move
    mv "$temp_file" "$STATS_AUTH_FILE"

    echo "✅ User '$username' removed successfully"
}

# Function to list users
list_users() {
    if [ ! -f "$STATS_AUTH_FILE" ]; then
        echo "📄 No stats auth file found at $STATS_AUTH_FILE"
        echo "Use '$0 add <username>' to create the first user"
        return
    fi

    echo "👥 Users in stats auth file:"
    echo "📁 File: $STATS_AUTH_FILE"
    echo ""
    cut -d: -f1 "$STATS_AUTH_FILE" | while read username; do
        echo "  • $username"
    done
    echo ""
    echo "File permissions: $(ls -la "$STATS_AUTH_FILE" | awk '{print $1, $3, $4}')"
}

# Function to verify dependencies
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo "❌ Error: openssl command not found. Please install openssl package."
        exit 1
    fi
}

# Main script logic
check_dependencies

case "$1" in
    "add")
        add_user "$2"
        ;;
    "remove")
        remove_user "$2"
        ;;
    "list")
        list_users
        ;;
    *)
        usage
        exit 1
        ;;
esac