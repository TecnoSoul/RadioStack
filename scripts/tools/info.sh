#!/bin/bash
# RadioStack - Info Tool
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script displays detailed information about RadioStack containers

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
# INFO FUNCTIONS
#=============================================================================

# Function: show_container_info
# Purpose: Display comprehensive information about a container
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
show_container_info() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Get inventory info
    init_inventory
    local hostname platform_type ip_address description created inv_status
    if [[ -f "$INVENTORY_FILE" ]]; then
        local entry
        entry=$(grep "^${ctid}," "$INVENTORY_FILE" 2>/dev/null || true)
        if [[ -n "$entry" ]]; then
            IFS=',' read -r _ platform_type hostname ip_address description created inv_status <<< "$entry"
        fi
    fi

    # Get container status
    local status
    status=$(get_container_status "$ctid")

    # Get config details
    local cores memory swap rootfs
    cores=$(pct config "$ctid" | grep "^cores:" | awk '{print $2}' || echo "N/A")
    memory=$(pct config "$ctid" | grep "^memory:" | awk '{print $2}' || echo "N/A")
    swap=$(pct config "$ctid" | grep "^swap:" | awk '{print $2}' || echo "N/A")
    rootfs=$(pct config "$ctid" | grep "^rootfs:" | awk '{print $2}' || echo "N/A")

    # Display information
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Container Information: $ctid"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Basic Information:"
    echo "  Container ID:       $ctid"
    echo "  Hostname:           ${hostname:-N/A}"
    echo "  Platform:           ${platform_type:-N/A}"
    echo "  Status:             $status"
    echo "  IP Address:         ${ip_address:-N/A}"
    echo ""
    echo "Resources:"
    echo "  CPU Cores:          $cores"
    echo "  Memory:             ${memory}MB"
    echo "  Swap:               ${swap}MB"
    echo "  Root Filesystem:    $rootfs"
    echo ""

    # Mount points
    echo "Mount Points:"
    local mount_points
    mount_points=$(pct config "$ctid" | grep "^mp[0-9]:" || echo "  None")
    if [[ "$mount_points" == "  None" ]]; then
        echo "$mount_points"
    else
        echo "$mount_points" | sed 's/^/  /'
    fi
    echo ""

    # Inventory details
    if [[ -n "${description:-}" ]]; then
        echo "Inventory Details:"
        echo "  Description:        $description"
        echo "  Created:            ${created:-N/A}"
        echo "  Inventory Status:   ${inv_status:-N/A}"
        echo ""
    fi

    # If container is running, get resource usage
    if [[ "$status" == "running" ]]; then
        echo "Resource Usage:"
        local cpu_usage mem_usage
        cpu_usage=$(pct exec "$ctid" -- top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' || echo "N/A")
        mem_usage=$(pct exec "$ctid" -- free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}' || echo "N/A")
        echo "  CPU Usage:          ${cpu_usage}%"
        echo "  Memory Usage:       $mem_usage"
        echo ""

        # Platform-specific info
        if [[ -n "${platform_type:-}" ]]; then
            case "$platform_type" in
                azuracast)
                    show_azuracast_info "$ctid"
                    ;;
                libretime)
                    show_libretime_info "$ctid"
                    ;;
            esac
        fi
    fi

    # ZFS dataset info
    if [[ -n "${platform_type:-}" ]] && [[ -n "${hostname:-}" ]]; then
        local station_name
        station_name=$(echo "$hostname" | sed "s/^${platform_type}-//")
        local dataset_path="hdd-pool/container-data/${platform_type}-media/${station_name}"

        if zfs list "$dataset_path" &>/dev/null; then
            echo "Storage Information:"
            echo "  Dataset:            $dataset_path"
            local used avail quota compressratio
            used=$(zfs get -H -o value used "$dataset_path")
            avail=$(zfs get -H -o value available "$dataset_path")
            quota=$(zfs get -H -o value quota "$dataset_path")
            compressratio=$(zfs get -H -o value compressratio "$dataset_path")
            echo "  Used:               $used"
            echo "  Available:          $avail"
            echo "  Quota:              $quota"
            echo "  Compression Ratio:  $compressratio"
            echo ""
        fi
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# Function: show_azuracast_info
# Purpose: Display AzuraCast-specific information
# Parameters:
#   $1 - ctid
# Returns: None
show_azuracast_info() {
    local ctid=$1

    echo "AzuraCast Information:"

    # Check if AzuraCast is installed
    if pct exec "$ctid" -- test -f /var/azuracast/docker.sh; then
        echo "  Installation:       /var/azuracast"

        # Get running containers
        local containers
        containers=$(pct exec "$ctid" -- docker ps --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
        echo "  Docker Containers:  $containers running"

        # Get version if available
        local version
        version=$(pct exec "$ctid" -- cat /var/azuracast/.env 2>/dev/null | grep "AZURACAST_VERSION" | cut -d'=' -f2 || echo "unknown")
        echo "  Version:            $version"
    else
        echo "  Installation:       Not found"
    fi
    echo ""
}

# Function: show_libretime_info
# Purpose: Display LibreTime-specific information
# Parameters:
#   $1 - ctid
# Returns: None
show_libretime_info() {
    local ctid=$1

    echo "LibreTime Information:"

    # Check if LibreTime is installed
    if pct exec "$ctid" -- test -f /opt/libretime/docker-compose.yml; then
        echo "  Installation:       /opt/libretime"

        # Get running services
        local services
        services=$(pct exec "$ctid" -- docker-compose -f /opt/libretime/docker-compose.yml ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
        echo "  Running Services:   $services"

        # Get version if available
        local version
        version=$(pct exec "$ctid" -- cat /opt/libretime/.env 2>/dev/null | grep "LIBRETIME_VERSION" | cut -d'=' -f2 || echo "unknown")
        echo "  Version:            $version"
    else
        echo "  Installation:       Not found"
    fi
    echo ""
}

# Function: show_system_summary
# Purpose: Display summary of entire RadioStack system
# Parameters: None
# Returns: 0 on success
show_system_summary() {
    init_inventory

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "RadioStack System Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Container counts
    local total azuracast_count libretime_count
    total=$(count_stations)
    azuracast_count=$(count_by_platform "azuracast")
    libretime_count=$(count_by_platform "libretime")

    echo "Station Count:"
    echo "  Total Stations:     $total"
    echo "  AzuraCast:          $azuracast_count"
    echo "  LibreTime:          $libretime_count"
    echo ""

    # Status breakdown
    if [[ $total -gt 0 ]]; then
        echo "Status Breakdown:"
        local running=0 stopped=0

        tail -n +2 "$INVENTORY_FILE" 2>/dev/null | while IFS=',' read -r ctid rest; do
            status=$(get_container_status "$ctid" 2>/dev/null || echo "unknown")
            if [[ "$status" == "running" ]]; then
                echo "running" >> /tmp/radiostack_status_count
            elif [[ "$status" == "stopped" ]]; then
                echo "stopped" >> /tmp/radiostack_status_count
            fi
        done

        if [[ -f /tmp/radiostack_status_count ]]; then
            running=$(grep -c "running" /tmp/radiostack_status_count 2>/dev/null || echo "0")
            stopped=$(grep -c "stopped" /tmp/radiostack_status_count 2>/dev/null || echo "0")
            rm /tmp/radiostack_status_count
        fi

        echo "  Running:            $running"
        echo "  Stopped:            $stopped"
        echo ""
    fi

    # Storage summary
    echo "Storage Pools:"
    if zpool list hdd-pool &>/dev/null; then
        local pool_health pool_size pool_free
        pool_health=$(zpool list -H -o health hdd-pool)
        pool_size=$(zpool list -H -o size hdd-pool)
        pool_free=$(zpool list -H -o free hdd-pool)
        echo "  Pool:               hdd-pool"
        echo "  Health:             $pool_health"
        echo "  Size:               $pool_size"
        echo "  Free:               $pool_free"
    else
        echo "  No ZFS pools found"
    fi
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

# Help message
show_help() {
    cat << EOF
RadioStack - Info Tool

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Show detailed info for specific container
    -s, --summary           Show system-wide summary (default)
    -h, --help              Show this help message

Examples:
    # Show system summary
    $0
    $0 --summary

    # Show detailed info for specific container
    $0 --ctid 340

EOF
    exit 0
}

# Parse arguments
MODE="summary"
CTID=""

if [[ $# -eq 0 ]]; then
    MODE="summary"
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ctid)
                MODE="container"
                CTID="$2"
                shift 2
                ;;
            -s|--summary)
                MODE="summary"
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
fi

# Execute based on mode
case "$MODE" in
    container)
        if [[ -z "$CTID" ]]; then
            log_error "Container ID is required"
            exit 1
        fi
        show_container_info "$CTID"
        ;;
    summary)
        show_system_summary
        ;;
esac
