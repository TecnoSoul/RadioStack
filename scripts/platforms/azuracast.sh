#!/bin/bash
# RadioStack - AzuraCast Platform Deployment
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script handles AzuraCast-specific deployment logic

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
# AZURACAST CONFIGURATION
#=============================================================================

# Default configuration (can be overridden by config file or parameters)
DEFAULT_AZURACAST_CORES=4
DEFAULT_AZURACAST_MEMORY=4092
DEFAULT_AZURACAST_QUOTA="50G"
DEFAULT_AZURACAST_RECORDSIZE="128k"
DEFAULT_AZURACAST_NETWORK="192.168.2"
DEFAULT_AZURACAST_CTID_RANGE_START=300
DEFAULT_AZURACAST_CTID_RANGE_END=399

# Load configuration if available
load_config 2>/dev/null || true

# Apply configuration with fallbacks
AZURACAST_CORES=$(get_config_value "DEFAULT_AZURACAST_CORES" "$DEFAULT_AZURACAST_CORES")
AZURACAST_MEMORY=$(get_config_value "DEFAULT_AZURACAST_MEMORY" "$DEFAULT_AZURACAST_MEMORY")
AZURACAST_QUOTA=$(get_config_value "DEFAULT_AZURACAST_QUOTA" "$DEFAULT_AZURACAST_QUOTA")
AZURACAST_RECORDSIZE=$(get_config_value "DEFAULT_AZURACAST_RECORDSIZE" "$DEFAULT_AZURACAST_RECORDSIZE")

#=============================================================================
# AZURACAST DEPLOYMENT FUNCTIONS
#=============================================================================

# Function: deploy_azuracast
# Purpose: Main deployment function for AzuraCast
# Parameters:
#   $1 - ctid
#   $2 - station_name
#   $3 - cores (optional)
#   $4 - memory (optional)
#   $5 - quota (optional)
#   $6 - ip_suffix (optional)
# Returns: 0 on success, 1 on failure
deploy_azuracast() {
    local ctid=$1
    local station_name=$2
    local cores=${3:-$AZURACAST_CORES}
    local memory=${4:-$AZURACAST_MEMORY}
    local quota=${5:-$AZURACAST_QUOTA}
    local ip_suffix=${6:-}

    # Validate required parameters
    if [[ -z "$ctid" ]] || [[ -z "$station_name" ]]; then
        log_error "Container ID and station name are required"
        return 1
    fi

    # Derive configuration
    local hostname="azuracast-${station_name}"

    # Auto-assign IP if not provided
    if [[ -z "$ip_suffix" ]]; then
        ip_suffix=$ctid
    fi
    local ip_address="${DEFAULT_AZURACAST_NETWORK}.${ip_suffix}"

    local media_dataset="hdd-pool/container-data/azuracast-media/${station_name}"
    local media_mount="/var/azuracast"

    # Display deployment information
    echo ""
    echo "========================================"
    echo "AzuraCast Container Deployment"
    echo "========================================"
    echo "Container ID:   $ctid"
    echo "Station Name:   $station_name"
    echo "Hostname:       $hostname"
    echo "IP Address:     $ip_address"
    echo "CPU Cores:      $cores"
    echo "Memory:         ${memory}MB"
    echo "Media Dataset:  $media_dataset"
    echo "Media Quota:    $quota"
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
    if ! create_media_dataset "$media_dataset" "$quota" "$AZURACAST_RECORDSIZE"; then
        log_error "Failed to create media dataset"
        return 1
    fi

    # Step 3: Create LXC container
    log_step "Creating LXC container..."
    if ! create_base_container "$ctid" "$hostname" "$cores" "$memory" "$ip_address" \
        "AzuraCast radio station - $station_name"; then
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

    # Step 8: Install AzuraCast
    log_step "Installing AzuraCast..."
    if ! install_azuracast "$ctid" "$media_mount"; then
        log_error "Failed to install AzuraCast"
        return 1
    fi

    # Step 9: Add to inventory
    log_step "Adding to inventory..."
    if ! add_to_inventory "$ctid" "azuracast" "$hostname" "$ip_address" "Station: $station_name"; then
        log_warn "Failed to add to inventory (non-fatal)"
    fi

    # Success!
    display_azuracast_success "$ctid" "$hostname" "$ip_address" "$media_mount"
    return 0
}

# Function: install_azuracast
# Purpose: Install AzuraCast using official Docker installer
# Parameters:
#   $1 - ctid
#   $2 - installation_path (e.g., /var/azuracast)
# Returns: 0 on success, 1 on failure
install_azuracast() {
    local ctid=$1
    local install_path=$2

    log_info "Downloading and installing AzuraCast..."

    if ! pct exec "$ctid" -- bash -c "
        set -e

        # Create installation directory
        mkdir -p '$install_path'
        cd '$install_path'

        # Download AzuraCast installer
        curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/main/docker.sh > docker.sh
        chmod a+x docker.sh

        # Use stable release and auto-accept prompts
        export DEBIAN_FRONTEND=noninteractive
        yes 'Y' | ./docker.sh setup-release || true
        yes '' | ./docker.sh install || true
    "; then
        log_error "AzuraCast installation failed"
        return 1
    fi

    log_success "AzuraCast installed successfully"
    return 0
}

# Function: display_azuracast_success
# Purpose: Display success message with access information
# Parameters:
#   $1 - ctid
#   $2 - hostname
#   $3 - ip_address
#   $4 - install_path
# Returns: None
display_azuracast_success() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3
    local install_path=$4

    echo ""
    echo "========================================"
    log_success "AzuraCast Deployment Complete!"
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
    echo "Next Steps:"
    echo "  1. Wait 2-3 minutes for AzuraCast to finish starting"
    echo "  2. Configure Nginx Proxy Manager for public access"
    echo "  3. Create admin account via web interface"
    echo "  4. Configure your radio station settings"
    echo ""
    echo "Management Commands:"
    echo "  Update:         pct exec $ctid -- $install_path/docker.sh update"
    echo "  Backup:         pct exec $ctid -- $install_path/docker.sh backup"
    echo "  Restore:        pct exec $ctid -- $install_path/docker.sh restore"
    echo "  Logs:           pct exec $ctid -- $install_path/docker.sh logs"
    echo "  Restart:        pct exec $ctid -- $install_path/docker.sh restart"
    echo ""
    echo "Documentation:"
    echo "  https://docs.azuracast.com"
    echo "========================================"
    echo ""
}

#=============================================================================
# AZURACAST MANAGEMENT FUNCTIONS
#=============================================================================

# Function: update_azuracast
# Purpose: Update AzuraCast installation
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
update_azuracast() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Updating AzuraCast in container $ctid..."

    if ! pct exec "$ctid" -- bash -c '
        if [[ -f /var/azuracast/docker.sh ]]; then
            cd /var/azuracast
            ./docker.sh update
        else
            echo "AzuraCast installation not found"
            exit 1
        fi
    '; then
        log_error "Update failed"
        return 1
    fi

    log_success "AzuraCast updated successfully"
    return 0
}

# Function: backup_azuracast
# Purpose: Backup AzuraCast data
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
backup_azuracast() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Creating backup of AzuraCast in container $ctid..."

    if ! pct exec "$ctid" -- bash -c '
        if [[ -f /var/azuracast/docker.sh ]]; then
            cd /var/azuracast
            ./docker.sh backup
        else
            echo "AzuraCast installation not found"
            exit 1
        fi
    '; then
        log_error "Backup failed"
        return 1
    fi

    log_success "Backup completed successfully"
    return 0
}

# Function: get_azuracast_logs
# Purpose: Display AzuraCast logs
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
get_azuracast_logs() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Fetching AzuraCast logs from container $ctid..."

    pct exec "$ctid" -- bash -c '
        if [[ -f /var/azuracast/docker.sh ]]; then
            cd /var/azuracast
            ./docker.sh logs
        else
            echo "AzuraCast installation not found"
            exit 1
        fi
    '
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
RadioStack - AzuraCast Deployment Script

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Station name (required)
    -c, --cores NUM         CPU cores (default: $AZURACAST_CORES)
    -m, --memory MB         Memory in MB (default: $AZURACAST_MEMORY)
    -q, --quota SIZE        Media storage quota (default: $AZURACAST_QUOTA)
    -p, --ip-suffix NUM     Last octet of IP (default: auto from CTID)
    -h, --help              Show this help message

Examples:
    # Basic deployment with defaults
    $0 -i 340 -n main

    # Custom configuration
    $0 -i 341 -n fm-rock -c 8 -m 16384 -q 1T -p 141

    # Auto-find available container ID
    CTID=\$(find_available_ctid 340 349)
    $0 -i \$CTID -n my-station

EOF
        exit 0
    }

    # Parse command-line arguments
    CTID=""
    STATION_NAME=""
    CORES=$AZURACAST_CORES
    MEMORY=$AZURACAST_MEMORY
    QUOTA=$AZURACAST_QUOTA
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
    deploy_azuracast "$CTID" "$STATION_NAME" "$CORES" "$MEMORY" "$QUOTA" "$IP_SUFFIX"
fi

# Export functions for use by other scripts
export -f deploy_azuracast install_azuracast
export -f update_azuracast backup_azuracast get_azuracast_logs
