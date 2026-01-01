#!/bin/bash
# RadioStack - Fix LibreTime Docker Compose Volume Mounts
# Purpose: Convert Docker volumes to host mounts for existing LibreTime deployments
# Usage: ./fix-libretime-volumes.sh -i CTID
#
# This script fixes the issue where LibreTime uses Docker volumes instead of
# the mounted HDD storage, causing media files to be stored on fast storage
# instead of bulk storage.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Usage information
show_help() {
    cat << EOF
RadioStack - Fix LibreTime Docker Compose Volume Mounts

This script fixes LibreTime deployments to use mounted HDD storage instead
of Docker volumes for media files.

Usage: $0 -i CTID [OPTIONS]

Required:
    -i, --ctid ID       Container ID

Options:
    -b, --backup        Create backup before modification (default: yes)
    -n, --no-backup     Skip backup creation
    -r, --restart       Restart services after fix (default: yes)
    -k, --keep-volume   Keep old Docker volume (default: remove)
    -h, --help          Show this help message

Examples:
    # Fix container 152 with defaults (backup + restart)
    $0 -i 152

    # Fix without restarting services
    $0 -i 152 --no-restart

    # Fix and keep old Docker volume
    $0 -i 152 --keep-volume

What this script does:
    1. Validates container exists and is running LibreTime
    2. Creates backup of docker-compose.yml (unless --no-backup)
    3. Replaces 'libretime_storage:/srv/libretime' with '/srv/libretime:/srv/libretime'
    4. Removes 'libretime_storage: {}' from volumes section
    5. Restarts Docker services (unless --no-restart)
    6. Removes old Docker volume (unless --keep-volume)
    7. Verifies the fix was applied correctly

EOF
    exit 0
}

# Default options
CTID=""
CREATE_BACKUP="yes"
RESTART_SERVICES="yes"
REMOVE_VOLUME="yes"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid) CTID="$2"; shift 2 ;;
        -b|--backup) CREATE_BACKUP="yes"; shift ;;
        -n|--no-backup) CREATE_BACKUP="no"; shift ;;
        -r|--restart) RESTART_SERVICES="yes"; shift ;;
        --no-restart) RESTART_SERVICES="no"; shift ;;
        -k|--keep-volume) REMOVE_VOLUME="no"; shift ;;
        -h|--help) show_help ;;
        *) log_error "Unknown option: $1"; show_help ;;
    esac
done

# Validate required parameters
if [[ -z "$CTID" ]]; then
    log_error "Container ID is required"
    show_help
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Check if container exists
if ! pct status "$CTID" &>/dev/null; then
    log_error "Container $CTID does not exist"
    exit 1
fi

# Check if container is running
STATUS=$(pct status "$CTID" | awk '{print $2}')
if [[ "$STATUS" != "running" ]]; then
    log_error "Container $CTID is not running (status: $STATUS)"
    exit 1
fi

# Check if LibreTime is installed
if ! pct exec "$CTID" -- test -f /opt/libretime/docker-compose.yml; then
    log_error "LibreTime installation not found in container $CTID"
    log_error "Expected file: /opt/libretime/docker-compose.yml"
    exit 1
fi

log_info "Starting LibreTime volume mount fix for container $CTID..."
echo ""

# Step 1: Check if fix is needed
log_info "Checking if fix is needed..."
if pct exec "$CTID" -- grep -q "libretime_storage:/srv/libretime" /opt/libretime/docker-compose.yml; then
    log_warn "Container needs volume mount fix (currently using Docker volumes)"
else
    log_success "Container already using host mounts - no fix needed!"
    
    # Verify it's actually correct
    if pct exec "$CTID" -- grep -q "/srv/libretime:/srv/libretime" /opt/libretime/docker-compose.yml; then
        log_success "Configuration is correct"
        exit 0
    else
        log_warn "Configuration is unclear - proceeding with fix anyway"
    fi
fi

# Step 2: Create backup
if [[ "$CREATE_BACKUP" == "yes" ]]; then
    log_info "Creating backup of docker-compose.yml..."
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    if pct exec "$CTID" -- cp /opt/libretime/docker-compose.yml "/opt/libretime/docker-compose.yml.backup-${TIMESTAMP}"; then
        log_success "Backup created: docker-compose.yml.backup-${TIMESTAMP}"
    else
        log_error "Failed to create backup"
        exit 1
    fi
fi

# Step 3: Stop services
if [[ "$RESTART_SERVICES" == "yes" ]]; then
    log_info "Stopping LibreTime services..."
    if pct exec "$CTID" -- docker-compose -f /opt/libretime/docker-compose.yml down; then
        log_success "Services stopped"
    else
        log_error "Failed to stop services"
        exit 1
    fi
fi

# Step 4: Apply the fix
log_info "Applying volume mount fix..."

FIX_SCRIPT=$(cat << 'EOFFIX'
cd /opt/libretime

# Replace Docker volume with host mount in all services
sed -i 's|libretime_storage:/srv/libretime|/srv/libretime:/srv/libretime|g' docker-compose.yml

# Remove libretime_storage from volumes section
sed -i '/^volumes:/,/^[^ ]/ {
    /libretime_storage:/d
}' docker-compose.yml

# Verify the changes
if grep -q "/srv/libretime:/srv/libretime" docker-compose.yml; then
    echo "SUCCESS"
else
    echo "FAILED"
fi
EOFFIX
)

RESULT=$(pct exec "$CTID" -- bash -c "$FIX_SCRIPT")

if [[ "$RESULT" == *"SUCCESS"* ]]; then
    log_success "Volume mount configuration updated"
else
    log_error "Failed to update volume mount configuration"
    if [[ "$CREATE_BACKUP" == "yes" ]]; then
        log_info "You can restore from backup: docker-compose.yml.backup-${TIMESTAMP}"
    fi
    exit 1
fi

# Step 5: Start services
if [[ "$RESTART_SERVICES" == "yes" ]]; then
    log_info "Starting LibreTime services..."
    if pct exec "$CTID" -- docker-compose -f /opt/libretime/docker-compose.yml up -d; then
        log_success "Services started"
    else
        log_error "Failed to start services"
        log_error "You may need to manually start: docker-compose -f /opt/libretime/docker-compose.yml up -d"
        exit 1
    fi
    
    # Wait a moment for services to initialize
    log_info "Waiting for services to initialize..."
    sleep 5
fi

# Step 6: Remove old Docker volume
if [[ "$REMOVE_VOLUME" == "yes" ]]; then
    log_info "Removing old Docker volume..."
    
    # Check if volume exists
    if pct exec "$CTID" -- docker volume ls | grep -q libretime_storage; then
        if pct exec "$CTID" -- docker volume rm libretime_storage 2>/dev/null; then
            log_success "Old Docker volume removed"
        else
            log_warn "Could not remove old Docker volume (may still be in use)"
            log_warn "It will be cleaned up automatically later"
        fi
    else
        log_info "Old Docker volume already removed or never existed"
    fi
fi

# Step 7: Verify the fix
log_info "Verifying configuration..."

# Check docker-compose.yml
if pct exec "$CTID" -- grep -q "/srv/libretime:/srv/libretime" /opt/libretime/docker-compose.yml; then
    log_success "docker-compose.yml: Using host mounts ✓"
else
    log_error "docker-compose.yml: Still using Docker volumes ✗"
    exit 1
fi

# Check that libretime_storage is removed from volumes section
if pct exec "$CTID" -- grep -q "libretime_storage:" /opt/libretime/docker-compose.yml; then
    log_warn "docker-compose.yml: libretime_storage still in volumes section (may be okay)"
else
    log_success "docker-compose.yml: libretime_storage removed from volumes section ✓"
fi

# Check if services are running (if we restarted them)
if [[ "$RESTART_SERVICES" == "yes" ]]; then
    log_info "Checking service status..."
    sleep 3  # Give services a moment to stabilize
    
    SERVICE_COUNT=$(pct exec "$CTID" -- docker-compose -f /opt/libretime/docker-compose.yml ps --services | wc -l)
    RUNNING_COUNT=$(pct exec "$CTID" -- docker-compose -f /opt/libretime/docker-compose.yml ps | grep "Up" | wc -l)
    
    if [[ $RUNNING_COUNT -ge 8 ]]; then
        log_success "Services: $RUNNING_COUNT/$SERVICE_COUNT running ✓"
    else
        log_warn "Services: Only $RUNNING_COUNT/$SERVICE_COUNT running"
        log_warn "Some services may still be starting up"
    fi
fi

# Step 8: Show summary
echo ""
echo "========================================"
log_success "Volume Mount Fix Complete!"
echo "========================================"
echo ""
echo "Container: $CTID"
echo "Configuration: /opt/libretime/docker-compose.yml"
if [[ "$CREATE_BACKUP" == "yes" ]]; then
    echo "Backup: docker-compose.yml.backup-${TIMESTAMP}"
fi
echo ""
echo "What changed:"
echo "  Before: libretime_storage:/srv/libretime (Docker volume)"
echo "  After:  /srv/libretime:/srv/libretime (Host mount)"
echo ""
echo "Media storage now correctly uses mounted HDD storage."
echo ""
echo "Next steps:"
echo "  1. Verify web interface: http://192.168.2.${CTID}:8080"
echo "  2. Check that music files are visible in library"
echo "  3. Test scheduling and playback"
echo ""
echo "Verify storage usage:"
echo "  pct exec $CTID -- df -h /srv/libretime"
echo ""
echo "View service logs:"
echo "  pct exec $CTID -- docker-compose -f /opt/libretime/docker-compose.yml logs -f"
echo ""
echo "========================================"

exit 0
