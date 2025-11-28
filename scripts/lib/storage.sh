#!/bin/bash
# RadioStack - Storage Library
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This library provides: ZFS dataset operations and storage management

set -euo pipefail

# Source common library for logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

#=============================================================================
# DATASET CREATION AND CONFIGURATION
#=============================================================================

# Function: create_media_dataset
# Purpose: Create ZFS dataset with optimal settings for media storage
# Parameters:
#   $1 - dataset_path (e.g., "hdd-pool/container-data/azuracast-media/station1")
#   $2 - quota (e.g., "500G", optional)
#   $3 - recordsize (optional, default: 128k for media)
# Returns: 0 on success, 1 on failure
# Example: create_media_dataset "hdd-pool/media/station1" "500G" "128k"
create_media_dataset() {
    local dataset_path=$1
    local quota=${2:-}
    local recordsize=${3:-128k}

    if [[ -z "$dataset_path" ]]; then
        log_error "Dataset path is required"
        return 1
    fi

    log_info "Creating ZFS dataset: $dataset_path"

    # Check if dataset already exists
    if zfs list "$dataset_path" &>/dev/null; then
        log_warn "Dataset already exists: $dataset_path"
        return 0
    fi

    # Extract pool name to verify it exists
    local pool_name
    pool_name=$(echo "$dataset_path" | cut -d'/' -f1)
    if ! check_storage_pool "$pool_name"; then
        log_error "Storage pool does not exist: $pool_name"
        return 1
    fi

    # Create dataset with parent directories
    if ! zfs create -p "$dataset_path"; then
        log_error "Failed to create dataset: $dataset_path"
        return 1
    fi

    # Set optimal properties for media storage
    log_info "Configuring dataset properties..."
    zfs set compression=lz4 "$dataset_path"
    zfs set recordsize="$recordsize" "$dataset_path"
    zfs set atime=off "$dataset_path"

    # Set quota if provided
    if [[ -n "$quota" ]]; then
        if ! zfs set quota="$quota" "$dataset_path"; then
            log_error "Failed to set quota: $quota"
            return 1
        fi
        log_info "Set quota: $quota"
    fi

    # Fix permissions for unprivileged containers (UID mapping)
    if ! fix_dataset_permissions "$dataset_path"; then
        log_error "Failed to set permissions"
        return 1
    fi

    log_success "Dataset created successfully: $dataset_path"
    return 0
}

# Function: delete_dataset
# Purpose: Safely remove ZFS dataset with confirmation
# Parameters:
#   $1 - dataset_path
#   $2 - force (optional, "yes" to skip confirmation)
# Returns: 0 on success, 1 on failure
# Example: delete_dataset "hdd-pool/media/station1"
delete_dataset() {
    local dataset_path=$1
    local force=${2:-no}

    if [[ -z "$dataset_path" ]]; then
        log_error "Dataset path is required"
        return 1
    fi

    # Check if dataset exists
    if ! zfs list "$dataset_path" &>/dev/null; then
        log_warn "Dataset does not exist: $dataset_path"
        return 0
    fi

    # Confirm deletion unless forced
    if [[ "$force" != "yes" ]]; then
        log_warn "This will permanently delete the dataset and all its data"
        if ! confirm_action "Delete dataset $dataset_path?" "n"; then
            log_info "Deletion cancelled"
            return 1
        fi
    fi

    log_info "Deleting dataset: $dataset_path"
    if ! zfs destroy -r "$dataset_path"; then
        log_error "Failed to delete dataset: $dataset_path"
        return 1
    fi

    log_success "Dataset deleted: $dataset_path"
    return 0
}

# Function: resize_dataset
# Purpose: Change quota on existing dataset
# Parameters:
#   $1 - dataset_path
#   $2 - new_quota (e.g., "1T")
# Returns: 0 on success, 1 on failure
# Example: resize_dataset "hdd-pool/media/station1" "1T"
resize_dataset() {
    local dataset_path=$1
    local new_quota=$2

    if [[ -z "$dataset_path" ]] || [[ -z "$new_quota" ]]; then
        log_error "Dataset path and quota are required"
        return 1
    fi

    # Check if dataset exists
    if ! zfs list "$dataset_path" &>/dev/null; then
        log_error "Dataset does not exist: $dataset_path"
        return 1
    fi

    log_info "Resizing dataset $dataset_path to $new_quota"
    if ! zfs set quota="$new_quota" "$dataset_path"; then
        log_error "Failed to resize dataset"
        return 1
    fi

    log_success "Dataset resized successfully"
    return 0
}

# Function: get_dataset_info
# Purpose: Get dataset details (used, available, quota)
# Parameters:
#   $1 - dataset_path
# Returns: 0 on success with info printed, 1 on failure
# Example: get_dataset_info "hdd-pool/media/station1"
get_dataset_info() {
    local dataset_path=$1

    if [[ -z "$dataset_path" ]]; then
        log_error "Dataset path is required"
        return 1
    fi

    if ! zfs list "$dataset_path" &>/dev/null; then
        log_error "Dataset does not exist: $dataset_path"
        return 1
    fi

    log_info "Dataset information: $dataset_path"
    zfs list -o name,used,avail,refer,quota,compressratio "$dataset_path"
    return 0
}

#=============================================================================
# STORAGE VALIDATION
#=============================================================================

# Function: check_storage_pool
# Purpose: Verify ZFS pool exists and is healthy
# Parameters:
#   $1 - pool_name
# Returns: 0 if pool exists and is healthy, 1 otherwise
# Example: check_storage_pool "hdd-pool" || die "Pool not available"
check_storage_pool() {
    local pool_name=$1

    if [[ -z "$pool_name" ]]; then
        log_error "Pool name is required"
        return 1
    fi

    # Check if pool exists
    if ! zpool list "$pool_name" &>/dev/null; then
        log_error "Storage pool not found: $pool_name"
        return 1
    fi

    # Check pool health
    local health
    health=$(zpool list -H -o health "$pool_name")
    if [[ "$health" != "ONLINE" ]]; then
        log_error "Pool $pool_name is not healthy (status: $health)"
        return 1
    fi

    return 0
}

# Function: validate_pool_space
# Purpose: Check if enough space is available in pool
# Parameters:
#   $1 - pool_name
#   $2 - required_space_gb (e.g., "100" for 100GB)
# Returns: 0 if enough space, 1 if insufficient
# Example: validate_pool_space "hdd-pool" "500" || die "Insufficient space"
validate_pool_space() {
    local pool_name=$1
    local required_gb=$2

    if [[ -z "$pool_name" ]] || [[ -z "$required_gb" ]]; then
        log_error "Pool name and required space are required"
        return 1
    fi

    if ! check_storage_pool "$pool_name"; then
        return 1
    fi

    # Get available space in GB
    local available_gb
    available_gb=$(zpool list -H -o free "$pool_name" | grep -o '[0-9.]*' | cut -d'.' -f1)

    if [[ $available_gb -lt $required_gb ]]; then
        log_error "Insufficient space in pool $pool_name"
        log_error "Available: ${available_gb}G, Required: ${required_gb}G"
        return 1
    fi

    log_info "Pool $pool_name has sufficient space (${available_gb}G available)"
    return 0
}

# Function: list_datasets
# Purpose: List all RadioStack datasets in a pool
# Parameters:
#   $1 - pool_name (optional, lists all if not provided)
#   $2 - filter_pattern (optional, e.g., "azuracast" or "libretime")
# Returns: 0 on success
# Example: list_datasets "hdd-pool" "azuracast"
list_datasets() {
    local pool_name=${1:-}
    local filter_pattern=${2:-container-data}

    if [[ -n "$pool_name" ]]; then
        if ! check_storage_pool "$pool_name"; then
            return 1
        fi
        log_info "Datasets in pool $pool_name:"
        zfs list -r -t filesystem "$pool_name" | grep "$filter_pattern" || log_warn "No datasets found"
    else
        log_info "All RadioStack datasets:"
        zfs list -t filesystem | grep "$filter_pattern" || log_warn "No datasets found"
    fi

    return 0
}

#=============================================================================
# PERMISSION MANAGEMENT
#=============================================================================

# Function: fix_dataset_permissions
# Purpose: Set correct ownership for unprivileged containers (UID mapping)
# Parameters:
#   $1 - dataset_path
# Returns: 0 on success, 1 on failure
# Example: fix_dataset_permissions "hdd-pool/media/station1"
fix_dataset_permissions() {
    local dataset_path=$1

    if [[ -z "$dataset_path" ]]; then
        log_error "Dataset path is required"
        return 1
    fi

    # Convert dataset path to filesystem path
    local mount_path="/$dataset_path"

    if [[ ! -d "$mount_path" ]]; then
        log_error "Dataset mount point does not exist: $mount_path"
        return 1
    fi

    log_info "Setting permissions for unprivileged container (100000:100000)"

    # Set ownership for unprivileged container UID mapping
    # Proxmox maps container UID 0 to host UID 100000
    if ! chown -R 100000:100000 "$mount_path"; then
        log_error "Failed to set ownership"
        return 1
    fi

    # Set readable/writable/executable for owner and group
    if ! chmod -R 755 "$mount_path"; then
        log_error "Failed to set permissions"
        return 1
    fi

    log_info "Permissions set successfully"
    return 0
}

#=============================================================================
# ADVANCED STORAGE OPERATIONS
#=============================================================================

# Function: create_snapshot
# Purpose: Create ZFS snapshot of dataset
# Parameters:
#   $1 - dataset_path
#   $2 - snapshot_name (optional, defaults to timestamp)
# Returns: 0 on success, 1 on failure
# Example: create_snapshot "hdd-pool/media/station1" "pre-update"
create_snapshot() {
    local dataset_path=$1
    local snapshot_name=${2:-$(date +%Y%m%d-%H%M%S)}

    if [[ -z "$dataset_path" ]]; then
        log_error "Dataset path is required"
        return 1
    fi

    if ! zfs list "$dataset_path" &>/dev/null; then
        log_error "Dataset does not exist: $dataset_path"
        return 1
    fi

    local snapshot_full="${dataset_path}@${snapshot_name}"
    log_info "Creating snapshot: $snapshot_full"

    if ! zfs snapshot "$snapshot_full"; then
        log_error "Failed to create snapshot"
        return 1
    fi

    log_success "Snapshot created: $snapshot_full"
    return 0
}

# Function: list_snapshots
# Purpose: List all snapshots for a dataset
# Parameters:
#   $1 - dataset_path
# Returns: 0 on success
# Example: list_snapshots "hdd-pool/media/station1"
list_snapshots() {
    local dataset_path=$1

    if [[ -z "$dataset_path" ]]; then
        log_error "Dataset path is required"
        return 1
    fi

    if ! zfs list "$dataset_path" &>/dev/null; then
        log_error "Dataset does not exist: $dataset_path"
        return 1
    fi

    log_info "Snapshots for $dataset_path:"
    zfs list -t snapshot -r "$dataset_path" || log_warn "No snapshots found"
    return 0
}

# Function: rollback_snapshot
# Purpose: Rollback dataset to a snapshot
# Parameters:
#   $1 - dataset_path
#   $2 - snapshot_name
# Returns: 0 on success, 1 on failure
# Example: rollback_snapshot "hdd-pool/media/station1" "pre-update"
rollback_snapshot() {
    local dataset_path=$1
    local snapshot_name=$2

    if [[ -z "$dataset_path" ]] || [[ -z "$snapshot_name" ]]; then
        log_error "Dataset path and snapshot name are required"
        return 1
    fi

    local snapshot_full="${dataset_path}@${snapshot_name}"

    if ! zfs list "$snapshot_full" &>/dev/null; then
        log_error "Snapshot does not exist: $snapshot_full"
        return 1
    fi

    log_warn "This will revert all changes since the snapshot was created"
    if ! confirm_action "Rollback to snapshot $snapshot_name?" "n"; then
        log_info "Rollback cancelled"
        return 1
    fi

    log_info "Rolling back to snapshot: $snapshot_full"
    if ! zfs rollback -r "$snapshot_full"; then
        log_error "Failed to rollback snapshot"
        return 1
    fi

    log_success "Rollback completed successfully"
    return 0
}

# Export functions
export -f create_media_dataset delete_dataset resize_dataset get_dataset_info
export -f check_storage_pool validate_pool_space list_datasets
export -f fix_dataset_permissions
export -f create_snapshot list_snapshots rollback_snapshot
