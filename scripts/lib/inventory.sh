#!/bin/bash
# RadioStack - Inventory Library
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This library provides: CSV-based station inventory tracking and management

set -euo pipefail

# Source common library for logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

# Inventory file location
INVENTORY_FILE="${INVENTORY_FILE:-/etc/radiostack/inventory/stations.csv}"
INVENTORY_BACKUP_DIR="${INVENTORY_BACKUP_DIR:-/etc/radiostack/inventory/backups}"

#=============================================================================
# INVENTORY INITIALIZATION
#=============================================================================

# Function: init_inventory
# Purpose: Create inventory file and directory structure if doesn't exist
# Parameters: None
# Returns: 0 on success, 1 on failure
# Example: init_inventory
init_inventory() {
    local inventory_dir
    inventory_dir=$(dirname "$INVENTORY_FILE")

    # Create inventory directory if it doesn't exist
    if [[ ! -d "$inventory_dir" ]]; then
        log_info "Creating inventory directory: $inventory_dir"
        if ! mkdir -p "$inventory_dir"; then
            log_error "Failed to create inventory directory"
            return 1
        fi
    fi

    # Create backup directory
    if [[ ! -d "$INVENTORY_BACKUP_DIR" ]]; then
        mkdir -p "$INVENTORY_BACKUP_DIR" || true
    fi

    # Create inventory file with header if it doesn't exist
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_info "Creating inventory file: $INVENTORY_FILE"
        echo "CTID,Type,Hostname,IP,Description,Created,Status" > "$INVENTORY_FILE"
        chmod 644 "$INVENTORY_FILE"
    fi

    return 0
}

# Function: backup_inventory
# Purpose: Create backup of inventory file before modifications
# Parameters: None
# Returns: 0 on success
# Example: backup_inventory
backup_inventory() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        return 0
    fi

    local backup_file
    backup_file="${INVENTORY_BACKUP_DIR}/stations-$(date +%Y%m%d-%H%M%S).csv"

    mkdir -p "$INVENTORY_BACKUP_DIR"
    cp "$INVENTORY_FILE" "$backup_file" 2>/dev/null || true

    # Keep only last 10 backups
    find "$INVENTORY_BACKUP_DIR" -name "stations-*.csv" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true

    return 0
}

#=============================================================================
# INVENTORY OPERATIONS
#=============================================================================

# Function: add_to_inventory
# Purpose: Add new station to inventory
# Parameters:
#   $1 - ctid
#   $2 - type (azuracast/libretime/icecast)
#   $3 - hostname
#   $4 - ip
#   $5 - description
# Returns: 0 on success, 1 on failure
# Example: add_to_inventory "340" "azuracast" "azuracast-main" "192.168.2.140" "Main station"
add_to_inventory() {
    local ctid=$1
    local type=$2
    local hostname=$3
    local ip=$4
    local description=$5

    if [[ -z "$ctid" ]] || [[ -z "$type" ]] || [[ -z "$hostname" ]] || [[ -z "$ip" ]]; then
        log_error "Missing required parameters for inventory entry"
        return 1
    fi

    # Initialize inventory if needed
    init_inventory

    # Check if entry already exists
    if grep -q "^${ctid}," "$INVENTORY_FILE" 2>/dev/null; then
        log_warn "Container $ctid already exists in inventory, updating..."
        remove_from_inventory "$ctid" "silent"
    fi

    # Backup before modification
    backup_inventory

    # Add entry with current date
    local created_date
    created_date=$(date +%Y-%m-%d)
    echo "$ctid,$type,$hostname,$ip,\"$description\",$created_date,active" >> "$INVENTORY_FILE"

    log_success "Added to inventory: $hostname (CTID: $ctid)"
    return 0
}

# Function: remove_from_inventory
# Purpose: Remove station entry from inventory
# Parameters:
#   $1 - ctid
#   $2 - mode (optional, "silent" to suppress messages)
# Returns: 0 on success, 1 on failure
# Example: remove_from_inventory "340"
remove_from_inventory() {
    local ctid=$1
    local mode=${2:-normal}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        [[ "$mode" != "silent" ]] && log_warn "Inventory file does not exist"
        return 0
    fi

    # Check if entry exists
    if ! grep -q "^${ctid}," "$INVENTORY_FILE"; then
        [[ "$mode" != "silent" ]] && log_warn "Container $ctid not found in inventory"
        return 0
    fi

    # Backup before modification
    backup_inventory

    # Remove entry (using temp file for safety)
    local temp_file
    temp_file=$(mktemp)
    grep -v "^${ctid}," "$INVENTORY_FILE" > "$temp_file"
    mv "$temp_file" "$INVENTORY_FILE"

    [[ "$mode" != "silent" ]] && log_success "Removed from inventory: CTID $ctid"
    return 0
}

# Function: update_inventory_status
# Purpose: Update status field for a station
# Parameters:
#   $1 - ctid
#   $2 - status (active/stopped/error/maintenance)
# Returns: 0 on success, 1 on failure
# Example: update_inventory_status "340" "maintenance"
update_inventory_status() {
    local ctid=$1
    local new_status=$2

    if [[ -z "$ctid" ]] || [[ -z "$new_status" ]]; then
        log_error "Container ID and status are required"
        return 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file does not exist"
        return 1
    fi

    # Check if entry exists
    if ! grep -q "^${ctid}," "$INVENTORY_FILE"; then
        log_error "Container $ctid not found in inventory"
        return 1
    fi

    # Backup before modification
    backup_inventory

    # Update status (modify the 7th field)
    local temp_file
    temp_file=$(mktemp)
    awk -F',' -v ctid="$ctid" -v status="$new_status" '
        BEGIN {OFS=","}
        $1 == ctid {$7 = status}
        {print}
    ' "$INVENTORY_FILE" > "$temp_file"
    mv "$temp_file" "$INVENTORY_FILE"

    log_success "Updated status for CTID $ctid to: $new_status"
    return 0
}

#=============================================================================
# QUERY OPERATIONS
#=============================================================================

# Function: list_all_stations
# Purpose: Display all stations in formatted table
# Parameters:
#   $1 - format (optional, "simple" for basic output, default: "table")
# Returns: 0 on success
# Example: list_all_stations
list_all_stations() {
    local format=${1:-table}

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "No inventory file found"
        return 0
    fi

    local count
    count=$(grep -c "^[0-9]" "$INVENTORY_FILE" || echo "0")

    if [[ $count -eq 0 ]]; then
        log_info "No stations in inventory"
        return 0
    fi

    log_info "RadioStack Inventory ($count stations):"
    echo ""

    if [[ "$format" == "table" ]]; then
        column -t -s ',' "$INVENTORY_FILE"
    else
        cat "$INVENTORY_FILE"
    fi

    echo ""
    return 0
}

# Function: list_by_platform
# Purpose: Filter stations by platform type
# Parameters:
#   $1 - type (azuracast/libretime/icecast)
# Returns: 0 on success
# Example: list_by_platform "azuracast"
list_by_platform() {
    local platform_type=$1

    if [[ -z "$platform_type" ]]; then
        log_error "Platform type is required"
        return 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "No inventory file found"
        return 0
    fi

    log_info "Stations running $platform_type:"
    echo ""

    # Filter by type (2nd column)
    local results
    results=$(grep -i "^[0-9]*,$platform_type," "$INVENTORY_FILE" 2>/dev/null || true)

    if [[ -z "$results" ]]; then
        log_info "No $platform_type stations found"
        return 0
    fi

    # Show header
    head -1 "$INVENTORY_FILE"
    echo "$results"
    echo "" | column -t -s ','

    return 0
}

# Function: get_station_info
# Purpose: Get detailed information for a single station
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 if not found
# Example: get_station_info "340"
get_station_info() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file does not exist"
        return 1
    fi

    # Get entry
    local entry
    entry=$(grep "^${ctid}," "$INVENTORY_FILE" 2>/dev/null || true)

    if [[ -z "$entry" ]]; then
        log_error "Container $ctid not found in inventory"
        return 1
    fi

    # Parse CSV fields
    IFS=',' read -r ctid_val type hostname ip description created status <<< "$entry"

    log_info "Station Information:"
    echo "─────────────────────────────────────"
    echo "Container ID:   $ctid_val"
    echo "Platform:       $type"
    echo "Hostname:       $hostname"
    echo "IP Address:     $ip"
    echo "Description:    $description"
    echo "Created:        $created"
    echo "Status:         $status"
    echo "─────────────────────────────────────"

    return 0
}

# Function: find_available_ctid
# Purpose: Find next available container ID in specified range
# Parameters:
#   $1 - start_range (e.g., "300")
#   $2 - end_range (e.g., "399")
# Returns: Echoes available CTID, returns 1 if none available
# Example: ctid=$(find_available_ctid "300" "399")
find_available_ctid() {
    local start_range=$1
    local end_range=$2

    if [[ -z "$start_range" ]] || [[ -z "$end_range" ]]; then
        log_error "Start and end range are required"
        return 1
    fi

    # Check each ID in range
    for ((ctid=start_range; ctid<=end_range; ctid++)); do
        # Check if exists in Proxmox
        if pct status "$ctid" &>/dev/null; then
            continue
        fi

        # Check if exists in inventory
        if [[ -f "$INVENTORY_FILE" ]] && grep -q "^${ctid}," "$INVENTORY_FILE"; then
            continue
        fi

        # Found available ID
        echo "$ctid"
        return 0
    done

    log_error "No available container IDs in range $start_range-$end_range"
    return 1
}

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

# Function: count_stations
# Purpose: Count total number of stations
# Parameters: None
# Returns: Echoes count
# Example: total=$(count_stations)
count_stations() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "0"
        return 0
    fi

    # grep -c outputs count but exits 1 when count is 0, so use || true to ignore exit code
    tail -n +2 "$INVENTORY_FILE" 2>/dev/null | grep -c "^[0-9]" || true
}

# Function: count_by_platform
# Purpose: Count stations by platform type
# Parameters:
#   $1 - type (azuracast/libretime/icecast)
# Returns: Echoes count
# Example: count=$(count_by_platform "azuracast")
count_by_platform() {
    local platform_type=$1

    if [[ -z "$platform_type" ]]; then
        echo "0"
        return 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "0"
        return 0
    fi

    # grep -c outputs count but exits 1 when count is 0, so use || true to ignore exit code
    tail -n +2 "$INVENTORY_FILE" 2>/dev/null | grep -ci "^[0-9]*,$platform_type," || true
}

# Function: export_inventory
# Purpose: Export inventory to JSON format
# Parameters:
#   $1 - output_file (path to JSON file)
# Returns: 0 on success, 1 on failure
# Example: export_inventory "/tmp/inventory.json"
export_inventory() {
    local output_file=$1

    if [[ -z "$output_file" ]]; then
        log_error "Output file path is required"
        return 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file does not exist"
        return 1
    fi

    log_info "Exporting inventory to JSON: $output_file"

    # Convert CSV to JSON using awk
    awk -F',' '
    BEGIN {
        print "{"
        print "  \"stations\": ["
        first = 1
    }
    NR > 1 {
        if (!first) print ","
        first = 0
        gsub(/"/, "", $5)  # Remove quotes from description
        printf "    {\n"
        printf "      \"ctid\": \"%s\",\n", $1
        printf "      \"type\": \"%s\",\n", $2
        printf "      \"hostname\": \"%s\",\n", $3
        printf "      \"ip\": \"%s\",\n", $4
        printf "      \"description\": \"%s\",\n", $5
        printf "      \"created\": \"%s\",\n", $6
        printf "      \"status\": \"%s\"\n", $7
        printf "    }"
    }
    END {
        print "\n  ]"
        print "}"
    }
    ' "$INVENTORY_FILE" > "$output_file"

    log_success "Inventory exported successfully"
    return 0
}

# Function: validate_inventory
# Purpose: Check inventory file integrity and fix common issues
# Parameters: None
# Returns: 0 if valid, 1 if issues found
# Example: validate_inventory
validate_inventory() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "Inventory file does not exist, initializing..."
        init_inventory
        return 0
    fi

    log_info "Validating inventory file..."

    local issues=0

    # Check header
    local header
    header=$(head -1 "$INVENTORY_FILE")
    if [[ "$header" != "CTID,Type,Hostname,IP,Description,Created,Status" ]]; then
        log_error "Invalid inventory header"
        ((issues++))
    fi

    # Check for duplicate CTIDs
    local duplicates
    duplicates=$(awk -F',' 'NR>1 {print $1}' "$INVENTORY_FILE" | sort | uniq -d)
    if [[ -n "$duplicates" ]]; then
        log_error "Duplicate CTIDs found: $duplicates"
        ((issues++))
    fi

    # Check for orphaned entries (containers that don't exist)
    local orphaned=0
    while IFS=',' read -r ctid rest; do
        if [[ "$ctid" =~ ^[0-9]+$ ]]; then
            if ! pct status "$ctid" &>/dev/null; then
                log_warn "Orphaned entry (container doesn't exist): CTID $ctid"
                ((orphaned++))
            fi
        fi
    done < <(tail -n +2 "$INVENTORY_FILE")

    if [[ $orphaned -gt 0 ]]; then
        log_warn "Found $orphaned orphaned entries (use cleanup command to remove)"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Inventory file is valid"
        return 0
    else
        log_error "Found $issues critical issues in inventory"
        return 1
    fi
}

# Function: cleanup_inventory
# Purpose: Remove orphaned entries (containers that no longer exist)
# Parameters: None
# Returns: 0 on success
# Example: cleanup_inventory
cleanup_inventory() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "Inventory file does not exist"
        return 0
    fi

    log_info "Cleaning up orphaned inventory entries..."

    backup_inventory

    local temp_file
    temp_file=$(mktemp)
    local removed=0

    # Keep header
    head -1 "$INVENTORY_FILE" > "$temp_file"

    # Check each entry
    while IFS=',' read -r ctid rest; do
        if [[ "$ctid" =~ ^[0-9]+$ ]]; then
            if pct status "$ctid" &>/dev/null; then
                echo "$ctid,$rest" >> "$temp_file"
            else
                log_warn "Removing orphaned entry: CTID $ctid"
                ((removed++))
            fi
        fi
    done < <(tail -n +2 "$INVENTORY_FILE")

    mv "$temp_file" "$INVENTORY_FILE"

    if [[ $removed -eq 0 ]]; then
        log_info "No orphaned entries found"
    else
        log_success "Removed $removed orphaned entries"
    fi

    return 0
}

# Export functions
export -f init_inventory backup_inventory
export -f add_to_inventory remove_from_inventory update_inventory_status
export -f list_all_stations list_by_platform get_station_info find_available_ctid
export -f count_stations count_by_platform export_inventory
export -f validate_inventory cleanup_inventory
