#!/bin/bash
# RadioStack - Update Tool
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script handles updates for RadioStack containers

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
source "$RADIOSTACK_ROOT/scripts/lib/inventory.sh"

# Source platform scripts
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/platforms/azuracast.sh"
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/platforms/libretime.sh"

#=============================================================================
# UPDATE FUNCTIONS
#=============================================================================

# Function: update_single_container
# Purpose: Update a single container by CTID
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
update_single_container() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Determine platform type from inventory
    init_inventory

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found - cannot determine platform type"
        return 1
    fi

    local platform_type
    platform_type=$(grep "^${ctid}," "$INVENTORY_FILE" | cut -d',' -f2)

    if [[ -z "$platform_type" ]]; then
        log_error "Container $ctid not found in inventory"
        return 1
    fi

    log_info "Updating $platform_type container $ctid..."

    case "$platform_type" in
        azuracast)
            update_azuracast "$ctid"
            ;;
        libretime)
            update_libretime "$ctid"
            ;;
        *)
            log_error "Unknown platform type: $platform_type"
            return 1
            ;;
    esac
}

# Function: update_all_platform
# Purpose: Update all containers of a specific platform
# Parameters:
#   $1 - platform (azuracast/libretime)
# Returns: 0 on success
update_all_platform() {
    local platform=$1

    if [[ -z "$platform" ]]; then
        log_error "Platform type is required"
        return 1
    fi

    init_inventory

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "No inventory file found"
        return 0
    fi

    local count
    count=$(count_by_platform "$platform")

    if [[ $count -eq 0 ]]; then
        log_info "No $platform containers found"
        return 0
    fi

    log_info "Updating all $platform containers ($count total)..."
    echo ""

    local success_count=0
    local fail_count=0

    grep -i "^[0-9]*,$platform," "$INVENTORY_FILE" 2>/dev/null | while IFS=',' read -r ctid type hostname rest; do
        log_step "Updating $hostname (CTID: $ctid)..."

        case "$platform" in
            azuracast)
                if update_azuracast "$ctid"; then
                    ((success_count++)) || true
                    log_success "Updated $hostname"
                else
                    ((fail_count++)) || true
                    log_error "Failed to update $hostname"
                fi
                ;;
            libretime)
                if update_libretime "$ctid"; then
                    ((success_count++)) || true
                    log_success "Updated $hostname"
                else
                    ((fail_count++)) || true
                    log_error "Failed to update $hostname"
                fi
                ;;
        esac

        echo ""
    done

    echo ""
    log_info "Update complete: $success_count succeeded, $fail_count failed"
    return 0
}

# Function: update_all_containers
# Purpose: Update all RadioStack containers regardless of platform
# Parameters: None
# Returns: 0 on success
update_all_containers() {
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

    log_info "Updating all RadioStack containers ($total_count total)..."
    echo ""

    if ! confirm_action "This will update ALL containers. Continue?" "n"; then
        log_info "Update cancelled"
        return 0
    fi

    echo ""

    tail -n +2 "$INVENTORY_FILE" | while IFS=',' read -r ctid type hostname rest; do
        log_step "Updating $hostname (CTID: $ctid, Platform: $type)..."

        case "$type" in
            azuracast)
                if update_azuracast "$ctid"; then
                    log_success "Updated $hostname"
                else
                    log_error "Failed to update $hostname"
                fi
                ;;
            libretime)
                if update_libretime "$ctid"; then
                    log_success "Updated $hostname"
                else
                    log_error "Failed to update $hostname"
                fi
                ;;
            *)
                log_warn "Unknown platform type: $type - skipping"
                ;;
        esac

        echo ""
    done

    log_success "All updates complete"
    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

# Help message
show_help() {
    cat << EOF
RadioStack - Update Tool

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Update specific container by ID
    -p, --platform TYPE     Update all containers of platform (azuracast/libretime)
    -a, --all               Update all containers (requires confirmation)
    -h, --help              Show this help message

Examples:
    # Update specific container
    $0 --ctid 340

    # Update all AzuraCast containers
    $0 --platform azuracast

    # Update all LibreTime containers
    $0 --platform libretime

    # Update ALL containers (requires confirmation)
    $0 --all

EOF
    exit 0
}

# Check root
check_root

# Parse arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid)
            CTID="$2"
            shift 2
            update_single_container "$CTID"
            exit $?
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            update_all_platform "$PLATFORM"
            exit $?
            ;;
        -a|--all)
            shift
            update_all_containers
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
