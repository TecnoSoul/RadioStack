#!/bin/bash
# RadioStack - Container Library
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This library provides: LXC container lifecycle and configuration operations

set -euo pipefail

# Source common library for logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

#=============================================================================
# CONTAINER LIFECYCLE
#=============================================================================

# Function: create_base_container
# Purpose: Create LXC container with standard RadioStack configuration
# Parameters:
#   $1 - ctid (container ID)
#   $2 - hostname
#   $3 - cores (CPU cores)
#   $4 - memory (RAM in MB)
#   $5 - ip_address (e.g., "192.168.2.140")
#   $6 - description (optional)
# Returns: 0 on success, 1 on failure
# Example: create_base_container "340" "azuracast-main" "6" "12288" "192.168.2.140" "Main station"
create_base_container() {
    local ctid=$1
    local hostname=$2
    local cores=$3
    local memory=$4
    local ip_address=$5
    local description=${6:-"RadioStack container"}

    # Validate inputs
    if [[ -z "$ctid" ]] || [[ -z "$hostname" ]] || [[ -z "$cores" ]] || [[ -z "$memory" ]] || [[ -z "$ip_address" ]]; then
        log_error "Missing required parameters for container creation"
        return 1
    fi

    if ! validate_ctid "$ctid"; then
        return 1
    fi

    if ! validate_ip "$ip_address"; then
        return 1
    fi

    log_info "Creating container $ctid ($hostname)"

    # Calculate swap as 1/4 of memory
    local swap=$((memory / 4))

    # Create container with standard configuration
    if ! pct create "$ctid" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
        --hostname "$hostname" \
        --description "$description" \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$swap" \
        --rootfs data:32 \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --net0 name=eth0,bridge=vmbr1,ip="${ip_address}/24",gw=192.168.2.1 \
        --nameserver 8.8.8.8 \
        --searchdomain tecnosoul.com.ar \
        --ostype debian \
        --start 0; then
        log_error "Failed to create container $ctid"
        return 1
    fi

    log_success "Container $ctid created successfully"
    return 0
}

# Function: start_container
# Purpose: Start container and wait for it to be ready
# Parameters:
#   $1 - ctid
#   $2 - wait (optional, "yes" to wait for boot, default: "yes")
# Returns: 0 on success, 1 on failure
# Example: start_container "340"
start_container() {
    local ctid=$1
    local wait_for_boot=${2:-yes}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Check if already running
    local status
    status=$(get_container_status "$ctid")
    if [[ "$status" == "running" ]]; then
        log_warn "Container $ctid is already running"
        return 0
    fi

    log_info "Starting container $ctid..."
    if ! pct start "$ctid"; then
        log_error "Failed to start container $ctid"
        return 1
    fi

    # Wait for container to be fully ready
    if [[ "$wait_for_boot" == "yes" ]]; then
        if ! wait_for_container "$ctid"; then
            return 1
        fi
    fi

    log_success "Container $ctid started successfully"
    return 0
}

# Function: stop_container
# Purpose: Stop container gracefully
# Parameters:
#   $1 - ctid
#   $2 - timeout (optional, seconds to wait before force stop, default: 60)
# Returns: 0 on success, 1 on failure
# Example: stop_container "340"
stop_container() {
    local ctid=$1
    local timeout=${2:-60}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Check if already stopped
    local status
    status=$(get_container_status "$ctid")
    if [[ "$status" == "stopped" ]]; then
        log_warn "Container $ctid is already stopped"
        return 0
    fi

    log_info "Stopping container $ctid..."
    if ! pct stop "$ctid" --timeout "$timeout"; then
        log_error "Failed to stop container $ctid"
        return 1
    fi

    log_success "Container $ctid stopped successfully"
    return 0
}

# Function: restart_container
# Purpose: Restart container
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
# Example: restart_container "340"
restart_container() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    log_info "Restarting container $ctid..."

    if ! stop_container "$ctid"; then
        return 1
    fi

    sleep 2

    if ! start_container "$ctid"; then
        return 1
    fi

    log_success "Container $ctid restarted successfully"
    return 0
}

# Function: delete_container
# Purpose: Remove container (with confirmation)
# Parameters:
#   $1 - ctid
#   $2 - force (optional, "yes" to skip confirmation)
# Returns: 0 on success, 1 on failure
# Example: delete_container "340"
delete_container() {
    local ctid=$1
    local force=${2:-no}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_warn "Container $ctid does not exist"
        return 0
    fi

    # Confirm deletion unless forced
    if [[ "$force" != "yes" ]]; then
        log_warn "This will permanently delete container $ctid"
        if ! confirm_action "Delete container $ctid?" "n"; then
            log_info "Deletion cancelled"
            return 1
        fi
    fi

    # Stop container if running
    local status
    status=$(get_container_status "$ctid")
    if [[ "$status" == "running" ]]; then
        log_info "Stopping container before deletion..."
        stop_container "$ctid" || true
    fi

    log_info "Deleting container $ctid..."
    if ! pct destroy "$ctid"; then
        log_error "Failed to delete container $ctid"
        return 1
    fi

    log_success "Container $ctid deleted successfully"
    return 0
}

#=============================================================================
# CONTAINER STATUS
#=============================================================================

# Function: container_exists
# Purpose: Check if container ID exists
# Parameters:
#   $1 - ctid
# Returns: 0 if exists, 1 if not
# Example: container_exists "340" || die "Container not found"
container_exists() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        return 1
    fi

    if pct status "$ctid" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: get_container_status
# Purpose: Get container status (running/stopped/etc)
# Parameters:
#   $1 - ctid
# Returns: Echoes status string, returns 1 if container doesn't exist
# Example: status=$(get_container_status "340")
get_container_status() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        echo "not-found"
        return 1
    fi

    local status
    status=$(pct status "$ctid" | awk '{print $2}')
    echo "$status"
    return 0
}

# Function: get_container_ip
# Purpose: Get IP address from running container
# Parameters:
#   $1 - ctid
# Returns: Echoes IP address, returns 1 on failure
# Example: ip=$(get_container_ip "340")
get_container_ip() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Extract IP from container config
    local ip
    ip=$(pct config "$ctid" | grep -oP 'ip=\K[^/]+' | head -1)

    if [[ -z "$ip" ]]; then
        log_error "Could not determine IP for container $ctid"
        return 1
    fi

    echo "$ip"
    return 0
}

# Function: wait_for_container
# Purpose: Wait until container is fully booted and ready
# Parameters:
#   $1 - ctid
#   $2 - max_wait (optional, seconds to wait, default: 60)
# Returns: 0 when ready, 1 on timeout
# Example: wait_for_container "340" 30
wait_for_container() {
    local ctid=$1
    local max_wait=${2:-60}
    local count=0

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    log_info "Waiting for container $ctid to be fully ready..."

    while [[ $count -lt $max_wait ]]; do
        # Check if systemd is running and system is operational
        if pct exec "$ctid" -- systemctl is-system-running --wait &>/dev/null; then
            log_success "Container is ready"
            return 0
        fi

        # Also accept "degraded" state as ready (some services may have issues)
        if pct exec "$ctid" -- systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; then
            log_success "Container is ready"
            return 0
        fi

        sleep 2
        ((count+=2))
        echo -n "."
    done

    echo ""
    log_warn "Container may not be fully ready, but continuing (timeout reached)"
    return 0
}

# Function: get_container_info
# Purpose: Display detailed container information
# Parameters:
#   $1 - ctid
# Returns: 0 on success
# Example: get_container_info "340"
get_container_info() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Container $ctid information:"
    pct config "$ctid"
    echo ""
    echo "Status: $(get_container_status "$ctid")"
    echo "IP Address: $(get_container_ip "$ctid" 2>/dev/null || echo 'N/A')"
    return 0
}

#=============================================================================
# CONTAINER CONFIGURATION
#=============================================================================

# Function: attach_mount_point
# Purpose: Add mount point to container
# Parameters:
#   $1 - ctid
#   $2 - mp_id (mount point ID, e.g., "0")
#   $3 - host_path (path on host)
#   $4 - container_path (path inside container)
# Returns: 0 on success, 1 on failure
# Example: attach_mount_point "340" "0" "/hdd-pool/media" "/var/azuracast"
attach_mount_point() {
    local ctid=$1
    local mp_id=$2
    local host_path=$3
    local container_path=$4

    if [[ -z "$ctid" ]] || [[ -z "$mp_id" ]] || [[ -z "$host_path" ]] || [[ -z "$container_path" ]]; then
        log_error "Missing required parameters for mount point"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    # Verify host path exists
    if [[ ! -d "$host_path" ]]; then
        log_error "Host path does not exist: $host_path"
        return 1
    fi

    log_info "Attaching mount point mp$mp_id: $host_path -> $container_path"

    if ! pct set "$ctid" -mp"$mp_id" "$host_path,mp=$container_path"; then
        log_error "Failed to attach mount point"
        return 1
    fi

    log_success "Mount point attached successfully"
    return 0
}

# Function: detach_mount_point
# Purpose: Remove mount point from container
# Parameters:
#   $1 - ctid
#   $2 - mp_id (mount point ID)
# Returns: 0 on success, 1 on failure
# Example: detach_mount_point "340" "0"
detach_mount_point() {
    local ctid=$1
    local mp_id=$2

    if [[ -z "$ctid" ]] || [[ -z "$mp_id" ]]; then
        log_error "Container ID and mount point ID are required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Detaching mount point mp$mp_id from container $ctid"

    if ! pct set "$ctid" -delete "mp$mp_id"; then
        log_error "Failed to detach mount point"
        return 1
    fi

    log_success "Mount point detached successfully"
    return 0
}

# Function: setup_container_system
# Purpose: Basic system setup inside container (updates, essentials, timezone)
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
# Example: setup_container_system "340"
setup_container_system() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    local status
    status=$(get_container_status "$ctid")
    if [[ "$status" != "running" ]]; then
        log_error "Container $ctid is not running"
        return 1
    fi

    log_step "Updating system and installing essentials in container $ctid"

    # Run system setup commands
    if ! pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update || exit 1
        apt-get dist-upgrade -y || exit 1
        apt-get install -y curl wget git ca-certificates gnupg sudo htop vim || exit 1
        timedatectl set-timezone America/Argentina/Buenos_Aires || exit 1
    '; then
        log_error "System setup failed"
        return 1
    fi

    log_success "System setup completed successfully"
    return 0
}

# Function: setup_docker
# Purpose: Install Docker inside container
# Parameters:
#   $1 - ctid
# Returns: 0 on success, 1 on failure
setup_docker() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_step "Installing Docker in container $ctid"

    if ! pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive

        # Add Docker repository
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Update package list
        apt-get update

        # Install Docker - let apt choose latest working versions
        # This avoids 404 errors when specific versions disappear from CDN
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
            # Fallback: Try with slightly older but stable versions
            echo "Retrying with pinned stable versions..."
            apt-get install -y \
                containerd.io=2.2.0-2~debian.13~trixie \
                docker-ce-cli=5:29.1.2-1~debian.13~trixie \
                docker-ce=5:29.1.2-1~debian.13~trixie \
                docker-buildx-plugin \
                docker-compose-plugin
        }

        # Start and enable Docker
        systemctl start docker
        systemctl enable docker
    '; then
        log_error "Docker installation failed"
        return 1
    fi

    log_success "Docker installed successfully"
    return 0
}
#=============================================================================
# CONTAINER OPERATIONS
#=============================================================================

# Function: exec_in_container
# Purpose: Execute command in container (wrapper for pct exec)
# Parameters:
#   $1 - ctid
#   $@ - command to execute
# Returns: Command exit code
# Example: exec_in_container "340" "ls -la /var/azuracast"
exec_in_container() {
    local ctid=$1
    shift

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    pct exec "$ctid" -- "$@"
}

# Function: enter_container
# Purpose: Enter container console (interactive shell)
# Parameters:
#   $1 - ctid
# Returns: Shell exit code
# Example: enter_container "340"
enter_container() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Entering container $ctid console..."
    pct enter "$ctid"
}

# Export functions
export -f create_base_container start_container stop_container restart_container delete_container
export -f container_exists get_container_status get_container_ip wait_for_container get_container_info
export -f attach_mount_point detach_mount_point setup_container_system setup_docker
export -f exec_in_container enter_container
