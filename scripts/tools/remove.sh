#!/bin/bash
# RadioStack - Remove Tool
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script handles removal of RadioStack containers and their data

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

#=============================================================================
# REMOVAL FUNCTIONS
#=============================================================================

# Function: remove_container
# Purpose: Remove a container and optionally its data
# Parameters:
#   $1 - ctid
#   $2 - remove_data (yes/no, default: no)
# Returns: 0 on success, 1 on failure
remove_container() {
    local ctid=$1
    local remove_data=${2:-no}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    # Get container info before deletion
    init_inventory

    local hostname platform_type dataset_path
    if [[ -f "$INVENTORY_FILE" ]]; then
        local entry
        entry=$(grep "^${ctid}," "$INVENTORY_FILE" 2>/dev/null || true)
        if [[ -n "$entry" ]]; then
            hostname=$(echo "$entry" | cut -d',' -f3)
            platform_type=$(echo "$entry" | cut -d',' -f2)
        fi
    fi

    # Determine dataset path based on platform
    if [[ -n "$platform_type" ]] && [[ -n "$hostname" ]]; then
        local station_name
        station_name=$(echo "$hostname" | sed "s/^${platform_type}-//")
        dataset_path="hdd-pool/container-data/${platform_type}-media/${station_name}"
    fi

    # Display removal information
    echo ""
    log_warn "Container Removal"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:   $ctid"
    [[ -n "${hostname:-}" ]] && echo "Hostname:       $hostname"
    [[ -n "${platform_type:-}" ]] && echo "Platform:       $platform_type"
    echo "Remove Data:    $remove_data"
    [[ -n "${dataset_path:-}" ]] && echo "Dataset:        $dataset_path"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Confirm removal
    log_warn "This action cannot be undone!"
    if ! confirm_action "Remove container $ctid?" "n"; then
        log_info "Removal cancelled"
        return 0
    fi

    # Step 1: Delete container
    log_step "Removing container $ctid..."
    if ! delete_container "$ctid" "yes"; then
        log_error "Failed to delete container"
        return 1
    fi

    # Step 2: Remove from inventory
    log_step "Removing from inventory..."
    remove_from_inventory "$ctid" || true

    # Step 3: Remove data if requested
    if [[ "$remove_data" == "yes" ]] && [[ -n "${dataset_path:-}" ]]; then
        echo ""
        log_warn "Data Removal"
        echo "This will permanently delete all media and configuration data"
        if confirm_action "Delete dataset $dataset_path?" "n"; then
            log_step "Deleting dataset..."
            if delete_dataset "$dataset_path" "yes"; then
                log_success "Dataset deleted"
            else
                log_error "Failed to delete dataset (may need manual cleanup)"
            fi
        else
            log_info "Dataset preserved: $dataset_path"
        fi
    fi

    echo ""
    log_success "Container $ctid removed successfully"

    if [[ "$remove_data" != "yes" ]] && [[ -n "${dataset_path:-}" ]]; then
        echo ""
        log_info "Note: Dataset was NOT removed: $dataset_path"
        log_info "To remove it later: zfs destroy -r $dataset_path"
    fi

    return 0
}

# Function: purge_all
# Purpose: Emergency removal of all RadioStack containers
# Parameters: None
# Returns: 0 on success
purge_all() {
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

    echo ""
    log_warn "⚠️  EMERGENCY PURGE - ALL RADIOSTACK CONTAINERS  ⚠️"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This will remove ALL $total_count RadioStack containers"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    list_all_stations

    echo ""
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    if ! confirm_action "Type 'DELETE' to confirm purge" "n"; then
        log_info "Purge cancelled"
        return 0
    fi

    read -rp "Type DELETE in capitals: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Purge cancelled"
        return 0
    fi

    echo ""
    log_step "Purging all containers..."

    tail -n +2 "$INVENTORY_FILE" | while IFS=',' read -r ctid type hostname rest; do
        log_info "Removing $hostname (CTID: $ctid)..."
        delete_container "$ctid" "yes" || log_error "Failed to delete $ctid"
    done

    # Clear inventory
    echo "CTID,Type,Hostname,IP,Description,Created,Status" > "$INVENTORY_FILE"

    log_success "Purge complete"
    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

# Help message
show_help() {
    cat << EOF
RadioStack - Remove Tool

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Remove specific container by ID (required)
    -d, --data              Also remove associated data (ZFS dataset)
    --purge-all             Remove ALL RadioStack containers (dangerous!)
    -h, --help              Show this help message

Examples:
    # Remove container, keep data
    $0 --ctid 340

    # Remove container and all its data
    $0 --ctid 340 --data

    # Emergency: Remove all RadioStack containers
    $0 --purge-all

EOF
    exit 0
}

# Check root
check_root

# Parse arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

CTID=""
REMOVE_DATA="no"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid)
            CTID="$2"
            shift 2
            ;;
        -d|--data)
            REMOVE_DATA="yes"
            shift
            ;;
        --purge-all)
            shift
            purge_all
            exit $?
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

if [[ -z "$CTID" ]]; then
    log_error "Container ID is required"
    show_help
fi

remove_container "$CTID" "$REMOVE_DATA"
