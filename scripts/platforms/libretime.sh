#!/bin/bash
# RadioStack - LibreTime Platform Deployment
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script handles LibreTime-specific deployment logic

set -euo pipefail

# Get script directory and RadioStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADIOSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library modules
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/storage.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/container.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/inventory.sh"

#=============================================================================
# LIBRETIME CONFIGURATION
#=============================================================================

# Default configuration (can be overridden by config file or parameters)
DEFAULT_LIBRETIME_CORES=2
DEFAULT_LIBRETIME_MEMORY=4092
DEFAULT_LIBRETIME_QUOTA="30G"
DEFAULT_LIBRETIME_RECORDSIZE="128k"
DEFAULT_LIBRETIME_NETWORK="192.168.2"
DEFAULT_LIBRETIME_CTID_RANGE_START=200
DEFAULT_LIBRETIME_CTID_RANGE_END=299
DEFAULT_LIBRETIME_VERSION="4.5.0"

# Load configuration if available
load_config 2>/dev/null || true

# Apply configuration with fallbacks
LIBRETIME_CORES=$(get_config_value "DEFAULT_LIBRETIME_CORES" "$DEFAULT_LIBRETIME_CORES")
LIBRETIME_MEMORY=$(get_config_value "DEFAULT_LIBRETIME_MEMORY" "$DEFAULT_LIBRETIME_MEMORY")
LIBRETIME_QUOTA=$(get_config_value "DEFAULT_LIBRETIME_QUOTA" "$DEFAULT_LIBRETIME_QUOTA")
LIBRETIME_RECORDSIZE=$(get_config_value "DEFAULT_LIBRETIME_RECORDSIZE" "$DEFAULT_LIBRETIME_RECORDSIZE")
LIBRETIME_VERSION=$(get_config_value "DEFAULT_LIBRETIME_VERSION" "$DEFAULT_LIBRETIME_VERSION")

#=============================================================================
# LIBRETIME DEPLOYMENT FUNCTIONS
#=============================================================================

# Function: deploy_libretime
# Purpose: Main deployment function for LibreTime
# Parameters:
#   $1 - ctid
#   $2 - station_name
#   $3 - cores (optional)
#   $4 - memory (optional)
#   $5 - quota (optional)
#   $6 - ip_suffix (optional)
# Returns: 0 on success, 1 on failure
deploy_libretime() {
    local ctid=$1
    local station_name=$2
    local cores=${3:-$LIBRETIME_CORES}
    local memory=${4:-$LIBRETIME_MEMORY}
    local quota=${5:-$LIBRETIME_QUOTA}
    local ip_suffix=${6:-}

    # Validate required parameters
    if [[ -z "$ctid" ]] || [[ -z "$station_name" ]]; then
        log_error "Container ID and station name are required"
        return 1
    fi

    # Derive configuration
    local hostname="libretime-${station_name}"

    # Auto-assign IP if not provided
    if [[ -z "$ip_suffix" ]]; then
        ip_suffix=$ctid
    fi
    local ip_address="${DEFAULT_LIBRETIME_NETWORK}.${ip_suffix}"

    local media_dataset="hdd-pool/container-data/libretime-media/${station_name}"
    local media_mount="/srv/libretime"
    local install_path="/opt/libretime"

    # Display deployment information
    echo ""
    echo "========================================"
    echo "LibreTime Container Deployment"
    echo "========================================"
    echo "Container ID:   $ctid"
    echo "Station Name:   $station_name"
    echo "Hostname:       $hostname"
    echo "IP Address:     $ip_address"
    echo "CPU Cores:      $cores"
    echo "Memory:         ${memory}MB"
    echo "Media Dataset:  $media_dataset"
    echo "Media Quota:    $quota"
    echo "Version:        $LIBRETIME_VERSION"
    echo "========================================"
    echo ""

    # Confirm deployment
    if ! confirm_action "Proceed with deployment?" "y"; then
        log_info "Deployment cancelled"
        return 1
    fi

    # Step 1: Validate environment
    log_step "Validating environment..."
    check_root
    check_proxmox_version || return 1

    if ! validate_ctid "$ctid"; then
        return 1
    fi

    # Step 2: Create ZFS dataset for media storage
    log_step "Creating ZFS dataset for media storage..."
    if ! create_media_dataset "$media_dataset" "$quota" "$LIBRETIME_RECORDSIZE"; then
        log_error "Failed to create media dataset"
        return 1
    fi

    # Step 3: Create LXC container
    log_step "Creating LXC container..."
    if ! create_base_container "$ctid" "$hostname" "$cores" "$memory" "$ip_address" \
        "LibreTime radio station - $station_name"; then
        log_error "Failed to create container"
        return 1
    fi

    # Step 4: Attach media storage
    log_step "Attaching media storage..."
    if ! attach_mount_point "$ctid" "0" "/$media_dataset" "$media_mount"; then
        log_error "Failed to attach mount point"
        return 1
    fi

    # Step 5: Start container
    log_step "Starting container..."
    if ! start_container "$ctid"; then
        log_error "Failed to start container"
        return 1
    fi

    # Step 6: System setup
    log_step "Setting up container system..."
    if ! setup_container_system "$ctid"; then
        log_error "Failed to setup container system"
        return 1
    fi

    # Step 7: Install Docker
    log_step "Installing Docker..."
    if ! setup_docker "$ctid"; then
        log_error "Failed to install Docker"
        return 1
    fi

    # Step 8: Install Docker Compose
    log_step "Installing Docker Compose..."
    if ! install_docker_compose "$ctid"; then
        log_error "Failed to install Docker Compose"
        return 1
    fi

    # Step 9: Install LibreTime
    log_step "Installing LibreTime..."
    if ! install_libretime "$ctid" "$install_path" "$media_mount"; then
        log_error "Failed to install LibreTime"
        return 1
    fi

    # Step 10: Add to inventory
    log_step "Adding to inventory..."
    if ! add_to_inventory "$ctid" "libretime" "$hostname" "$ip_address" "Station: $station_name"; then
        log_warn "Failed to add to inventory (non-fatal)"
    fi

    # Success!
    display_libretime_success "$ctid" "$hostname" "$ip_address" "$install_path"
    return 0
}

# Function: install_docker_compose
# Purpose: Install Docker Compose standalone
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
install_docker_compose() {
    local ctid=$1

    log_info "Installing Docker Compose..."

    if ! pct exec "$ctid" -- bash -c '
        set -e

        # Download latest Docker Compose
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose

        # Make executable
        chmod +x /usr/local/bin/docker-compose

        # Create symbolic link
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

        # Verify installation
        docker-compose --version
    '; then
        log_error "Docker Compose installation failed"
        return 1
    fi

    log_success "Docker Compose installed successfully"
    return 0
}

# Function: install_libretime
# Purpose: Install LibreTime using official Docker setup
# Parameters:
#   $1 - ctid
#   $2 - installation_path (e.g., /opt/libretime)
#   $3 - media_path (e.g., /srv/libretime)
# Returns: 0 on success, 1 on failure
install_libretime() {
    local ctid=$1
    local install_path=$2
    local media_path=$3

    log_info "Downloading and installing LibreTime..."

    if ! pct exec "$ctid" -- bash -c "
        set -e

        # Create installation directory
        mkdir -p '$install_path'
        cd '$install_path'

        # Install envsubst for config template processing
        apt-get update -qq
        apt-get install -y -qq gettext-base

        # Set LibreTime version
        echo \"LIBRETIME_VERSION=\$LIBRETIME_VERSION\" > .env

        # Download LibreTime files
        wget -q \"https://raw.githubusercontent.com/libretime/libretime/\$LIBRETIME_VERSION/docker-compose.yml\"
        wget -q \"https://raw.githubusercontent.com/libretime/libretime/\$LIBRETIME_VERSION/docker/config.template.yml\"
        wget -q \"https://raw.githubusercontent.com/libretime/libretime/\$LIBRETIME_VERSION/docker/nginx.conf\"

        # Generate secure random passwords
        echo \"\" >> .env
        echo \"# Database Configuration\" >> .env
        echo \"POSTGRES_PASSWORD=\$(openssl rand -base64 32)\" >> .env
        echo \"\" >> .env
        echo \"# RabbitMQ Configuration\" >> .env
        echo \"RABBITMQ_DEFAULT_PASS=\$(openssl rand -base64 32)\" >> .env
        echo \"\" >> .env
        echo \"# Icecast Configuration\" >> .env
        echo \"ICECAST_SOURCE_PASSWORD=\$(openssl rand -base64 32)\" >> .env
        echo \"ICECAST_ADMIN_PASSWORD=\$(openssl rand -base64 32)\" >> .env
        echo \"ICECAST_RELAY_PASSWORD=\$(openssl rand -base64 32)\" >> .env

        # Generate configuration file
        set -a
        source .env
        set +a
        envsubst < config.template.yml > config.yml

        # Get container IP address for public_url
        CONTAINER_IP=\$(hostname -I | awk '{print \$1}')

        # Generate API key and secret key
        API_KEY=\$(openssl rand -hex 32)
        SECRET_KEY=\$(openssl rand -hex 32)

        # Configure required LibreTime settings
        # Update public_url with container IP
        sed -i \"s|public_url:.*|public_url: http://\${CONTAINER_IP}|g\" config.yml

        # Update api_key
        sed -i \"s|api_key:.*|api_key: \${API_KEY}|g\" config.yml

        # Update secret_key
        sed -i \"s|secret_key:.*|secret_key: \${SECRET_KEY}|g\" config.yml

        # Update configuration for external media path
        sed -i 's|storage_path:.*|storage_path: $media_path|g' config.yml

        # Ensure media directory has correct permissions
        mkdir -p '$media_path'
        chown -R 1000:1000 '$media_path' || true

        # Start LibreTime services
        docker-compose up -d

        # Wait for services to initialize
        echo \"Waiting for services to start...\"
        sleep 45

        # Initialize database
        docker-compose exec -T libretime bash -c 'cd /var/www/libretime && php artisan migrate --force' || true
    "; then
        log_error "LibreTime installation failed"
        return 1
    fi

    log_success "LibreTime installed successfully"
    return 0
}

# Function: display_libretime_success
# Purpose: Display success message with access information
# Parameters:
#   $1 - ctid
#   $2 - hostname
#   $3 - ip_address
#   $4 - install_path
# Returns: None
display_libretime_success() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3
    local install_path=$4

    echo ""
    echo "========================================"
    log_success "LibreTime Deployment Complete!"
    echo "========================================"
    echo ""
    echo "Container Information:"
    echo "  CTID:           $ctid"
    echo "  Hostname:       $hostname"
    echo "  Internal IP:    http://$ip_address"
    echo ""
    echo "Access:"
    echo "  Web Interface:  http://$ip_address"
    echo "  Console:        pct enter $ctid"
    echo ""
    echo "Default Credentials:"
    echo "  Username:       admin"
    echo "  Password:       admin"
    echo "  ⚠️  CHANGE IMMEDIATELY AFTER LOGIN!"
    echo ""
    echo "Next Steps:"
    echo "  1. Wait 2-3 minutes for all services to fully start"
    echo "  2. Access web interface and login with default credentials"
    echo "  3. Change admin password immediately"
    echo "  4. Configure Nginx Proxy Manager for public access"
    echo "  5. Configure your streaming outputs (Icecast/Shoutcast)"
    echo "  6. Upload media and create playlists"
    echo ""
    echo "Management Commands:"
    echo "  Logs:           pct exec $ctid -- docker-compose -f $install_path/docker-compose.yml logs"
    echo "  Restart:        pct exec $ctid -- docker-compose -f $install_path/docker-compose.yml restart"
    echo "  Stop:           pct exec $ctid -- docker-compose -f $install_path/docker-compose.yml stop"
    echo "  Start:          pct exec $ctid -- docker-compose -f $install_path/docker-compose.yml start"
    echo "  Status:         pct exec $ctid -- docker-compose -f $install_path/docker-compose.yml ps"
    echo ""
    echo "Configuration Files:"
    echo "  Docker Compose: $install_path/docker-compose.yml"
    echo "  LibreTime:      $install_path/config.yml"
    echo "  Environment:    $install_path/.env"
    echo ""
    echo "Documentation:"
    echo "  https://libretime.org/docs"
    echo "========================================"
    echo ""
}

#=============================================================================
# LIBRETIME MANAGEMENT FUNCTIONS
#=============================================================================

# Function: update_libretime
# Purpose: Update LibreTime installation
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
update_libretime() {
    local ctid=$1
    local install_path="/opt/libretime"

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Updating LibreTime in container $ctid..."

    if ! pct exec "$ctid" -- bash -c "
        if [[ -f $install_path/docker-compose.yml ]]; then
            cd $install_path
            docker-compose pull
            docker-compose up -d
            docker-compose exec -T libretime bash -c 'cd /var/www/libretime && php artisan migrate --force'
        else
            echo 'LibreTime installation not found'
            exit 1
        fi
    "; then
        log_error "Update failed"
        return 1
    fi

    log_success "LibreTime updated successfully"
    return 0
}

# Function: backup_libretime
# Purpose: Backup LibreTime configuration and database
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
backup_libretime() {
    local ctid=$1
    local install_path="/opt/libretime"

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    local backup_dir="/root/libretime-backups"
    local timestamp=$(date +%Y%m%d-%H%M%S)

    log_info "Creating backup of LibreTime in container $ctid..."

    if ! pct exec "$ctid" -- bash -c "
        set -e

        if [[ ! -f $install_path/docker-compose.yml ]]; then
            echo 'LibreTime installation not found'
            exit 1
        fi

        # Create backup directory
        mkdir -p $backup_dir

        cd $install_path

        # Backup database
        docker-compose exec -T postgres pg_dump -U libretime libretime > $backup_dir/libretime-db-$timestamp.sql

        # Backup configuration
        tar czf $backup_dir/libretime-config-$timestamp.tar.gz .env config.yml docker-compose.yml

        echo \"Backup saved to $backup_dir/\"
        ls -lh $backup_dir/*$timestamp*
    "; then
        log_error "Backup failed"
        return 1
    fi

    log_success "Backup completed successfully"
    return 0
}

# Function: get_libretime_logs
# Purpose: Display LibreTime logs
# Parameters:
#   $1 - ctid
#   $2 - service (optional, specific service name)
# Returns: 0 on success, 1 on failure
get_libretime_logs() {
    local ctid=$1
    local service=${2:-}
    local install_path="/opt/libretime"

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Fetching LibreTime logs from container $ctid..."

    if [[ -n "$service" ]]; then
        pct exec "$ctid" -- docker-compose -f "$install_path/docker-compose.yml" logs "$service"
    else
        pct exec "$ctid" -- docker-compose -f "$install_path/docker-compose.yml" logs
    fi
}

#=============================================================================
# SCRIPT EXECUTION (when called directly)
#=============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly, not sourced

    # Help message
    show_help() {
        cat << EOF
RadioStack - LibreTime Deployment Script

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Station name (required)
    -c, --cores NUM         CPU cores (default: $LIBRETIME_CORES)
    -m, --memory MB         Memory in MB (default: $LIBRETIME_MEMORY)
    -q, --quota SIZE        Media storage quota (default: $LIBRETIME_QUOTA)
    -p, --ip-suffix NUM     Last octet of IP (default: auto from CTID)
    -h, --help              Show this help message

Examples:
    # Basic deployment with defaults
    $0 -i 350 -n station1

    # Custom configuration
    $0 -i 351 -n fm-classic -c 6 -m 12288 -q 500G -p 151

    # Auto-find available container ID
    CTID=\$(find_available_ctid 350 359)
    $0 -i \$CTID -n my-station

EOF
        exit 0
    }

    # Parse command-line arguments
    CTID=""
    STATION_NAME=""
    CORES=$LIBRETIME_CORES
    MEMORY=$LIBRETIME_MEMORY
    QUOTA=$LIBRETIME_QUOTA
    IP_SUFFIX=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ctid) CTID="$2"; shift 2 ;;
            -n|--name) STATION_NAME="$2"; shift 2 ;;
            -c|--cores) CORES="$2"; shift 2 ;;
            -m|--memory) MEMORY="$2"; shift 2 ;;
            -q|--quota) QUOTA="$2"; shift 2 ;;
            -p|--ip-suffix) IP_SUFFIX="$2"; shift 2 ;;
            -h|--help) show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$CTID" ]] || [[ -z "$STATION_NAME" ]]; then
        log_error "Container ID and station name are required"
        show_help
    fi

    # Execute deployment
    deploy_libretime "$CTID" "$STATION_NAME" "$CORES" "$MEMORY" "$QUOTA" "$IP_SUFFIX"
fi

# Export functions for use by other scripts
export -f deploy_libretime install_libretime install_docker_compose
export -f update_libretime backup_libretime get_libretime_logs
