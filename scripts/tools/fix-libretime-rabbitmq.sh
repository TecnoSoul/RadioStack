#!/bin/bash
# RadioStack - Fix LibreTime RabbitMQ Password Issue
# Regenerates passwords without special characters

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADIOSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$RADIOSTACK_ROOT/scripts/lib/common.sh"

show_help() {
    cat << EOF
RadioStack - Fix LibreTime RabbitMQ Password

Fixes the "Port could not be cast to integer" error by regenerating
RabbitMQ password without special characters that break URL parsing.

Usage: $0 -i CTID

Options:
    -i, --ctid ID       Container ID (required)
    -h, --help          Show this help

Example:
    $0 -i 163

EOF
    exit 0
}

CTID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid) CTID="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) log_error "Unknown option: $1"; show_help ;;
    esac
done

if [[ -z "$CTID" ]]; then
    log_error "Container ID is required"
    show_help
fi

log_info "Fixing RabbitMQ password in container $CTID..."

pct exec "$CTID" -- bash -c '
    set -e
    cd /opt/libretime

    # Backup files
    cp .env .env.backup.$(date +%Y%m%d-%H%M%S)
    cp config.yml config.yml.backup.$(date +%Y%m%d-%H%M%S)

    # Generate new hex-encoded passwords (no special chars)
    NEW_RABBITMQ_PASS=$(openssl rand -hex 32)
    NEW_POSTGRES_PASS=$(openssl rand -hex 32)
    NEW_ICECAST_SOURCE=$(openssl rand -hex 32)
    NEW_ICECAST_ADMIN=$(openssl rand -hex 32)
    NEW_ICECAST_RELAY=$(openssl rand -hex 32)

    # Update .env file
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${NEW_POSTGRES_PASS}/" .env
    sed -i "s/^RABBITMQ_DEFAULT_PASS=.*/RABBITMQ_DEFAULT_PASS=${NEW_RABBITMQ_PASS}/" .env
    sed -i "s/^ICECAST_SOURCE_PASSWORD=.*/ICECAST_SOURCE_PASSWORD=${NEW_ICECAST_SOURCE}/" .env
    sed -i "s/^ICECAST_ADMIN_PASSWORD=.*/ICECAST_ADMIN_PASSWORD=${NEW_ICECAST_ADMIN}/" .env
    sed -i "s/^ICECAST_RELAY_PASSWORD=.*/ICECAST_RELAY_PASSWORD=${NEW_ICECAST_RELAY}/" .env

    # Regenerate config.yml with new passwords
    set -a
    source .env
    set +a
    envsubst < config.template.yml > config.yml.new

    # Preserve custom settings from old config
    OLD_PUBLIC_URL=$(grep "public_url:" config.yml | head -1 | sed "s/.*public_url: //")
    OLD_API_KEY=$(grep "api_key:" config.yml | head -1 | sed "s/.*api_key: //")
    OLD_SECRET_KEY=$(grep "secret_key:" config.yml | head -1 | sed "s/.*secret_key: //")
    OLD_STORAGE=$(grep "storage_path:" config.yml | head -1 | sed "s/.*storage_path: //")
    OLD_CORS=$(grep -A 100 "allowed_cors_origins:" config.yml | grep -m 1 "\[" | sed "s/.*\[/[/")

    # Apply custom settings to new config
    sed -i "s|public_url:.*|public_url: ${OLD_PUBLIC_URL}|" config.yml.new
    sed -i "s|api_key:.*|api_key: ${OLD_API_KEY}|" config.yml.new
    sed -i "s|secret_key:.*|secret_key: ${OLD_SECRET_KEY}|" config.yml.new
    sed -i "s|storage_path:.*|storage_path: ${OLD_STORAGE}|" config.yml.new
    sed -i "s|allowed_cors_origins:.*|allowed_cors_origins: ${OLD_CORS}|" config.yml.new

    # Replace old config with new one
    mv config.yml.new config.yml

    echo "Passwords regenerated successfully"
    echo "Stopping services..."
    docker-compose down

    echo "Starting services with new passwords..."
    docker-compose up -d

    echo "Waiting for services to start..."
    sleep 20

    echo "Checking service status..."
    docker-compose ps
'

log_success "RabbitMQ password fixed in container $CTID"
log_info "Please check the playout logs for the error to be gone:"
log_info "  pct exec $CTID -- docker-compose -f /opt/libretime/docker-compose.yml logs playout --tail 30"
