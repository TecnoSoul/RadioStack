#!/bin/bash
# RadioStack - Fix AzuraCast Storage Configuration
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script fixes existing AzuraCast deployments to use mounted HDD storage
# instead of Docker volumes on fast storage

set -euo pipefail

# Get script directory and RadioStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADIOSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library modules
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/container.sh"

#=============================================================================
# STORAGE FIX FUNCTION
#=============================================================================

# Function: fix_azuracast_storage
# Purpose: Migrate AzuraCast from Docker volumes to mounted HDD storage
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
fix_azuracast_storage() {
    local ctid=$1
    local install_path="/var/azuracast"

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    echo ""
    echo "========================================"
    echo "AzuraCast Storage Configuration Fix"
    echo "========================================"
    echo "Container ID:   $ctid"
    echo "Install Path:   $install_path"
    echo ""
    echo "This will:"
    echo "  1. Stop AzuraCast services"
    echo "  2. Backup current docker-compose.yml"
    echo "  3. Migrate station data to mounted HDD"
    echo "  4. Update docker-compose.yml to use HDD path"
    echo "  5. Restart services"
    echo ""

    if ! confirm_action "Proceed with storage fix?" "y"; then
        log_info "Operation cancelled"
        return 1
    fi

    log_step "Checking current storage configuration..."

    # Check if already using mounted storage
    if pct exec "$ctid" -- grep -q "$install_path/stations:/var/azuracast/stations" "$install_path/docker-compose.yml" 2>/dev/null; then
        log_success "Storage is already configured correctly!"
        echo "Using mounted path: $install_path/stations"
        return 0
    fi

    log_step "Stopping AzuraCast services..."
    if ! pct exec "$ctid" -- bash -c "cd $install_path && docker compose down"; then
        log_error "Failed to stop services"
        return 1
    fi

    log_step "Migrating station data to mounted storage..."
    if ! pct exec "$ctid" -- bash -c "
        set -e

        # Create stations directory on mounted HDD
        mkdir -p '$install_path/stations'

        # Check if Docker volume exists and has data
        if docker volume inspect azuracast_station_data >/dev/null 2>&1; then
            echo 'Found existing station_data volume, migrating data...'

            # Mount volume and copy data
            TEMP_CONTAINER=\$(docker run -d -v azuracast_station_data:/source alpine tail -f /dev/null)
            docker cp \$TEMP_CONTAINER:/source/. '$install_path/stations/'
            docker stop \$TEMP_CONTAINER
            docker rm \$TEMP_CONTAINER

            echo 'Data migration complete'
        else
            echo 'No existing station data found, starting fresh'
        fi

        # Set correct permissions
        chown -R 1000:1000 '$install_path/stations'
        chmod -R 755 '$install_path/stations'
    "; then
        log_error "Failed to migrate data"
        return 1
    fi

    log_step "Updating docker-compose.yml..."
    if ! pct exec "$ctid" -- bash -c "
        set -e
        cd '$install_path'

        # Backup original
        cp docker-compose.yml docker-compose.yml.bak.\$(date +%Y%m%d_%H%M%S)

        # Replace Docker volume with mounted path
        sed -i 's|station_data:/var/azuracast/stations|$install_path/stations:/var/azuracast/stations:rw|g' docker-compose.yml

        # Remove the station_data volume definition
        sed -i '/^volumes:/,/^[^ ]/ {
            /station_data:/d
        }' docker-compose.yml

        # Clean up empty volumes section
        sed -i '/^volumes:$/,/^[^ ]/ {
            /^volumes:$/ {
                N
                /^volumes:\n[^ ]/ {
                    s/^volumes:\n//
                }
            }
        }' docker-compose.yml

        echo 'Configuration updated successfully'
    "; then
        log_error "Failed to update configuration"
        return 1
    fi

    log_step "Restarting AzuraCast services..."
    if ! pct exec "$ctid" -- bash -c "cd $install_path && docker compose up -d"; then
        log_error "Failed to start services"
        return 1
    fi

    log_step "Cleaning up old Docker volume..."
    pct exec "$ctid" -- docker volume rm azuracast_station_data 2>/dev/null || true

    echo ""
    echo "========================================"
    log_success "Storage Fix Complete!"
    echo "========================================"
    echo ""
    echo "Verification:"
    echo "  Storage mount:  pct exec $ctid -- df -h $install_path"
    echo "  Configuration:  pct exec $ctid -- grep '$install_path/stations' $install_path/docker-compose.yml"
    echo "  Station files:  pct exec $ctid -- ls -la $install_path/stations/"
    echo ""
    echo "Your media files are now stored on the mounted HDD!"
    echo ""

    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

# Help message
show_help() {
    cat << EOF
RadioStack - Fix AzuraCast Storage Configuration

Usage: $0 --ctid ID

Options:
    --ctid ID       Container ID to fix (required)
    -h, --help      Show this help message

Description:
    This script fixes existing AzuraCast deployments that are using Docker
    volumes on fast storage instead of the mounted HDD storage.

    It will:
    - Migrate existing station data from Docker volume to HDD
    - Update docker-compose.yml to use mounted path
    - Preserve all existing media files and settings

Examples:
    # Fix container 232
    $0 --ctid 232

    # Fix container 340
    sudo ./scripts/tools/fix-azuracast-storage.sh --ctid 340

EOF
    exit 0
}

# Parse command-line arguments
CTID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --ctid) CTID="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) log_error "Unknown option: $1"; show_help ;;
    esac
done

# Validate required parameters
if [[ -z "$CTID" ]]; then
    log_error "Container ID is required"
    show_help
fi

# Check root
check_root

# Execute fix
fix_azuracast_storage "$CTID"
