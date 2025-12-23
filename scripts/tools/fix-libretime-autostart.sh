#!/bin/bash
# RadioStack - Fix LibreTime Auto-start on Reboot
# Adds restart policies to existing LibreTime deployments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADIOSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library
source "$RADIOSTACK_ROOT/scripts/lib/common.sh"

# Help message
show_help() {
    cat << EOF
RadioStack - Fix LibreTime Auto-start

This script adds restart policies to existing LibreTime containers
so they automatically start after host reboot.

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID       Container ID (required)
    -h, --help          Show this help message

Example:
    $0 -i 163

What it does:
    1. Adds "restart: unless-stopped" to all services in docker-compose.yml
    2. Enables Docker service to start on boot
    3. Tests the configuration

EOF
    exit 0
}

# Parse arguments
CTID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid) CTID="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) log_error "Unknown option: $1"; show_help ;;
    esac
done

# Validate
if [[ -z "$CTID" ]]; then
    log_error "Container ID is required"
    show_help
fi

log_info "Configuring auto-start for LibreTime container $CTID..."

# Execute fix
pct exec "$CTID" -- bash -c '
    set -e
    cd /opt/libretime

    # Backup original docker-compose.yml
    cp docker-compose.yml docker-compose.yml.backup

    # Add restart policy to all services
    echo "Adding restart policies..."

    # Check if restart policies already exist
    if grep -q "restart:" docker-compose.yml; then
        echo "Restart policies already configured"
    else
        # Add restart: unless-stopped after each service declaration
        sed -i "/^  postgres:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  rabbitmq:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  playout:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  liquidsoap:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  analyzer:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  worker:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  api:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  legacy:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  nginx:/a\    restart: unless-stopped" docker-compose.yml
        sed -i "/^  icecast:/a\    restart: unless-stopped" docker-compose.yml

        echo "Restart policies added successfully"
    fi

    # Enable Docker service
    echo "Enabling Docker service..."
    systemctl enable docker

    # Apply changes
    echo "Applying configuration..."
    docker-compose up -d

    echo "Configuration complete!"
    echo ""
    echo "To test auto-start, reboot the container:"
    echo "  pct reboot '"$CTID"'"
    echo ""
    echo "After reboot, verify services are running:"
    echo "  pct exec '"$CTID"' -- docker-compose -f /opt/libretime/docker-compose.yml ps"
'

log_success "Auto-start configured for container $CTID"
