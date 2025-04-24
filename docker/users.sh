#!/bin/bash

# Script to manage stats authentication users

STATS_AUTH_FILE="/opt/sfu/docker/nginx/ssl/stats_auth"

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

generate_hash() {
    local password=$1
    openssl passwd -apr1 "$password"
}

add_user() {
    local username=$1
    if [ -z "$username" ]; then
        echo "❌ Error: Username is required"
        usage
        exit 1
    fi

    if [[ "$username" == *":"* ]] || [[ "$username" == *" "* ]]; then
        echo "❌ Error: Username cannot contain colons or spaces"
        exit 1
    fi

    mkdir -p $(dirname "$STATS_AUTH_FILE")

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

    local hash=$(generate_hash "$password")
    local auth_line="$username:$hash"

    local temp_file="${STATS_AUTH_FILE}.tmp"

    if [ -f "$STATS_AUTH_FILE" ]; then
        grep -v "^$username:" "$STATS_AUTH_FILE" > "$temp_file" 2>/dev/null || true
    else
        touch "$temp_file"
    fi

    echo "$auth_line" >> "$temp_file"

    mv "$temp_file" "$STATS_AUTH_FILE"

    chmod 644 "$STATS_AUTH_FILE"

    echo "✅ User '$username' added/updated successfully"
    echo "📁 File location: $STATS_AUTH_FILE"
}

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

    if ! grep -q "^$username:" "$STATS_AUTH_FILE"; then
        echo "❌ Error: User '$username' not found"
        exit 1
    fi

    local temp_file="${STATS_AUTH_FILE}.tmp"
    grep -v "^$username:" "$STATS_AUTH_FILE" > "$temp_file"

    mv "$temp_file" "$STATS_AUTH_FILE"

    echo "✅ User '$username' removed successfully"
}

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

check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo "❌ Error: openssl command not found. Please install openssl package."
        exit 1
    fi
}

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