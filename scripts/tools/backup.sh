#!/bin/bash
# RadioStack - Backup Tool
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script handles backups for RadioStack containers

set -euo pipefail

# Get script directory and RadioStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADIOSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library modules
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/container.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/storage.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/inventory.sh"

# Source platform scripts
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/platforms/azuracast.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/platforms/libretime.sh"

#=============================================================================
# BACKUP CONFIGURATION
#=============================================================================

# Default backup configuration
DEFAULT_BACKUP_STORAGE="hdd-backups"
DEFAULT_BACKUP_MODE="snapshot"
DEFAULT_BACKUP_COMPRESS="zstd"

# Load configuration if available
load_config 2>/dev/null || true

BACKUP_STORAGE=$(get_config_value "DEFAULT_BACKUP_STORAGE" "$DEFAULT_BACKUP_STORAGE")
BACKUP_MODE=$(get_config_value "DEFAULT_BACKUP_MODE" "$DEFAULT_BACKUP_MODE")
BACKUP_COMPRESS=$(get_config_value "DEFAULT_BACKUP_COMPRESS" "$DEFAULT_BACKUP_COMPRESS")

#=============================================================================
# BACKUP FUNCTIONS
#=============================================================================

# Function: backup_single_container
# Purpose: Backup a single container
# Parameters:
#   $1 - ctid
#   $2 - backup_type (container/application/full, default: container)
# Returns: 0 on success, 1 on failure
backup_single_container() {
    local ctid=$1
    local backup_type=${2:-container}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Get container info
    init_inventory
    local hostname platform_type
    if [[ -f "$INVENTORY_FILE" ]]; then
        local entry
        entry=$(grep "^${ctid}," "$INVENTORY_FILE" 2>/dev/null || true)
        if [[ -n "$entry" ]]; then
            hostname=$(echo "$entry" | cut -d',' -f3)
            platform_type=$(echo "$entry" | cut -d',' -f2)
        fi
    fi

    log_info "Starting backup of container $ctid (${hostname:-unknown})"
    echo ""

    case "$backup_type" in
        container)
            # Full container backup using vzdump
            backup_container_vzdump "$ctid" "$hostname"
            ;;
        application)
            # Application-level backup
            backup_application_data "$ctid" "$platform_type"
            ;;
        full)
            # Both container and ZFS snapshot
            backup_container_vzdump "$ctid" "$hostname"
            backup_zfs_dataset "$ctid" "$hostname" "$platform_type"
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac
}

# Function: backup_container_vzdump
# Purpose: Backup container using Proxmox vzdump
# Parameters:
#   $1 - ctid
#   $2 - hostname (optional, for logging)
# Returns: 0 on success, 1 on failure
backup_container_vzdump() {
    local ctid=$1
    local hostname=${2:-container-$ctid}

    log_step "Creating vzdump backup of $hostname ($ctid)..."

    if ! vzdump "$ctid" \
        --storage "$BACKUP_STORAGE" \
        --mode "$BACKUP_MODE" \
        --compress "$BACKUP_COMPRESS"; then
        log_error "Vzdump backup failed"
        return 1
    fi

    log_success "Container backup completed"
    return 0
}

# Function: backup_application_data
# Purpose: Backup application-specific data
# Parameters:
#   $1 - ctid
#   $2 - platform_type
# Returns: 0 on success, 1 on failure
backup_application_data() {
    local ctid=$1
    local platform_type=$2

    if [[ -z "$platform_type" ]]; then
        log_warn "Platform type unknown, skipping application backup"
        return 0
    fi

    log_step "Creating application-level backup..."

    case "$platform_type" in
        azuracast)
            backup_azuracast "$ctid"
            ;;
        libretime)
            backup_libretime "$ctid"
            ;;
        *)
            log_warn "No application backup available for platform: $platform_type"
            return 0
            ;;
    esac
}

# Function: backup_zfs_dataset
# Purpose: Create ZFS snapshot of dataset
# Parameters:
#   $1 - ctid
#   $2 - hostname
#   $3 - platform_type
# Returns: 0 on success, 1 on failure
backup_zfs_dataset() {
    local ctid=$1
    local hostname=$2
    local platform_type=$3

    if [[ -z "$platform_type" ]]; then
        log_warn "Platform type unknown, skipping ZFS backup"
        return 0
    fi

    # Determine dataset path
    local station_name
    station_name=$(echo "$hostname" | sed "s/^${platform_type}-//")
    local dataset_path="hdd-pool/container-data/${platform_type}-media/${station_name}"

    if ! zfs list "$dataset_path" &>/dev/null; then
        log_warn "Dataset not found: $dataset_path"
        return 0
    fi

    log_step "Creating ZFS snapshot of $dataset_path..."

    local snapshot_name="backup-$(date +%Y%m%d-%H%M%S)"
    if ! create_snapshot "$dataset_path" "$snapshot_name"; then
        log_error "Failed to create ZFS snapshot"
        return 1
    fi

    log_success "ZFS snapshot created: ${dataset_path}@${snapshot_name}"
    return 0
}

# Function: backup_all_containers
# Purpose: Backup all RadioStack containers
# Parameters:
#   $1 - backup_type (container/application/full, default: container)
# Returns: 0 on success
backup_all_containers() {
    local backup_type=${1:-container}

    init_inventory

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "No inventory file found"
        return 0
    fi

    local total_count
    total_count=$(count_stations)

    if [[ $total_count -eq 0 ]]; then
        log_info "No containers found in inventory"
        return 0
    fi

    log_info "Starting backup of all RadioStack containers ($total_count total)"
    echo ""

    local success_count=0
    local fail_count=0

    tail -n +2 "$INVENTORY_FILE" | while IFS=',' read -r ctid type hostname rest; do
        log_step "Backing up $hostname (CTID: $ctid)..."

        if backup_single_container "$ctid" "$backup_type"; then
            ((success_count++)) || true
            log_success "Backed up $hostname"
        else
            ((fail_count++)) || true
            log_error "Failed to backup $hostname"
        fi

        echo ""
    done

    echo ""
    log_info "Backup complete: $success_count succeeded, $fail_count failed"
    return 0
}

# Function: list_backups
# Purpose: List available backups for a container
# Parameters:
#   $1 - ctid (optional, lists all if not provided)
# Returns: 0 on success
list_backups() {
    local ctid=${1:-}

    log_info "Available backups:"
    echo ""

    # List vzdump backups
    if [[ -n "$ctid" ]]; then
        pvesm list "$BACKUP_STORAGE" | grep "vzdump-lxc-${ctid}-" || log_warn "No backups found for container $ctid"
    else
        pvesm list "$BACKUP_STORAGE" | grep "vzdump-lxc-" || log_warn "No backups found"
    fi

    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

# Help message
show_help() {
    cat << EOF
RadioStack - Backup Tool

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Backup specific container by ID
    -a, --all               Backup all containers
    -t, --type TYPE         Backup type: container/application/full (default: container)
    -l, --list [ID]         List available backups (optionally for specific container)
    -h, --help              Show this help message

Backup Types:
    container               Full container backup using vzdump (default)
    application             Application-level backup (AzuraCast/LibreTime)
    full                    Both container and ZFS snapshot

Examples:
    # Backup specific container (full container backup)
    $0 --ctid 340

    # Backup container with application data
    $0 --ctid 340 --type application

    # Full backup (container + ZFS snapshot)
    $0 --ctid 340 --type full

    # Backup all containers
    $0 --all

    # List all backups
    $0 --list

    # List backups for specific container
    $0 --list --ctid 340

EOF
    exit 0
}

# Check root
check_root

# Parse arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

MODE=""
CTID=""
BACKUP_TYPE="container"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid)
            CTID="$2"
            shift 2
            ;;
        -a|--all)
            MODE="all"
            shift
            ;;
        -t|--type)
            BACKUP_TYPE="$2"
            shift 2
            ;;
        -l|--list)
            MODE="list"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Execute based on mode
case "$MODE" in
    list)
        list_backups "$CTID"
        ;;
    all)
        backup_all_containers "$BACKUP_TYPE"
        ;;
    *)
        if [[ -z "$CTID" ]]; then
            log_error "Container ID is required"
            show_help
        fi
        backup_single_container "$CTID" "$BACKUP_TYPE"
        ;;
esac
