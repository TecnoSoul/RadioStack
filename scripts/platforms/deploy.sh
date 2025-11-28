#!/bin/bash
# RadioStack - Platform Deployment Dispatcher
# Part of RadioStack unified radio platform deployment system
# https://github.com/TecnoSoul/RadioStack
#
# This script routes deployment requests to the appropriate platform handler

set -euo pipefail

# Get script directory and RadioStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RADIOSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library modules
# shellcheck disable=SC1091
source "$RADIOSTACK_ROOT/scripts/lib/common.sh"

#=============================================================================
# PLATFORM DISPATCHER
#=============================================================================

# Function: show_help
# Purpose: Display help message
show_help() {
    cat << EOF
RadioStack - Platform Deployment Dispatcher

Usage: $0 <platform> [OPTIONS]

Platforms:
    azuracast       Deploy AzuraCast radio platform
    libretime       Deploy LibreTime radio platform
    icecast         Deploy standalone Icecast server (future)

Common Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Station name (required)
    -c, --cores NUM         CPU cores (platform defaults)
    -m, --memory MB         Memory in MB (platform defaults)
    -q, --quota SIZE        Media storage quota (platform defaults)
    -p, --ip-suffix NUM     Last octet of IP (auto from CTID)
    -h, --help              Show this help message

Examples:
    # Deploy AzuraCast
    $0 azuracast -i 340 -n main

    # Deploy LibreTime
    $0 libretime -i 350 -n station1

    # Deploy with custom resources
    $0 azuracast -i 341 -n fm-rock -c 8 -m 16384 -q 1T

Platform-Specific Help:
    $0 azuracast --help
    $0 libretime --help

EOF
    exit 0
}

# Function: deploy_platform
# Purpose: Route deployment to appropriate platform handler
# Parameters:
#   $1 - platform (azuracast/libretime/icecast)
#   $@ - additional arguments passed to platform script
# Returns: Platform script exit code
deploy_platform() {
    local platform=$1
    shift

    case "$platform" in
        azuracast)
            # shellcheck disable=SC1091
            source "$SCRIPT_DIR/azuracast.sh"

            # Parse arguments for azuracast
            local ctid="" station_name="" cores="" memory="" quota="" ip_suffix=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -i|--ctid) ctid="$2"; shift 2 ;;
                    -n|--name) station_name="$2"; shift 2 ;;
                    -c|--cores) cores="$2"; shift 2 ;;
                    -m|--memory) memory="$2"; shift 2 ;;
                    -q|--quota) quota="$2"; shift 2 ;;
                    -p|--ip-suffix) ip_suffix="$2"; shift 2 ;;
                    -h|--help)
                        bash "$SCRIPT_DIR/azuracast.sh" --help
                        exit 0
                        ;;
                    *) log_error "Unknown option: $1"; exit 1 ;;
                esac
            done

            if [[ -z "$ctid" ]] || [[ -z "$station_name" ]]; then
                log_error "Container ID and station name are required"
                exit 1
            fi

            deploy_azuracast "$ctid" "$station_name" "$cores" "$memory" "$quota" "$ip_suffix"
            ;;

        libretime)
            # shellcheck disable=SC1091
            source "$SCRIPT_DIR/libretime.sh"

            # Parse arguments for libretime
            local ctid="" station_name="" cores="" memory="" quota="" ip_suffix=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -i|--ctid) ctid="$2"; shift 2 ;;
                    -n|--name) station_name="$2"; shift 2 ;;
                    -c|--cores) cores="$2"; shift 2 ;;
                    -m|--memory) memory="$2"; shift 2 ;;
                    -q|--quota) quota="$2"; shift 2 ;;
                    -p|--ip-suffix) ip_suffix="$2"; shift 2 ;;
                    -h|--help)
                        bash "$SCRIPT_DIR/libretime.sh" --help
                        exit 0
                        ;;
                    *) log_error "Unknown option: $1"; exit 1 ;;
                esac
            done

            if [[ -z "$ctid" ]] || [[ -z "$station_name" ]]; then
                log_error "Container ID and station name are required"
                exit 1
            fi

            deploy_libretime "$ctid" "$station_name" "$cores" "$memory" "$quota" "$ip_suffix"
            ;;

        icecast)
            log_error "Icecast deployment is not yet implemented"
            log_info "Coming in a future release"
            exit 1
            ;;

        *)
            log_error "Unknown platform: $platform"
            log_info "Supported platforms: azuracast, libretime"
            show_help
            ;;
    esac
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

# Check if any arguments provided
if [[ $# -eq 0 ]]; then
    show_help
fi

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
fi

# Get platform and remaining arguments
PLATFORM=$1
shift

# Dispatch to platform handler
deploy_platform "$PLATFORM" "$@"
