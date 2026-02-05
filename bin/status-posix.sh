#!/bin/bash
#
# status-posix.sh - Show status of the zgw-posix S3 gateway container
#
# Usage: ./status-posix.sh [OPTIONS]
#
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
CONTAINER_NAME="zgw-posix"

# Script options
VERBOSE=false

# =============================================================================
# Colors
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
debug()   { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $*" || true; }
header()  { echo -e "${CYAN}=== $* ===${NC}"; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Show status of the zgw-posix S3 gateway container.

Options:
  -h, --help          Show this help message and exit
  -v, --verbose       Enable verbose output (show more details)
  --name NAME         Container name to check (default: $CONTAINER_NAME)

Examples:
  # Show basic status
  $SCRIPT_NAME

  # Show detailed status
  $SCRIPT_NAME -v

EOF
    exit 0
}

# =============================================================================
# Argument Parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Dependency Checks
# =============================================================================
check_dependencies() {
    if ! command -v podman &> /dev/null; then
        error "podman is not installed or not in PATH"
        exit 1
    fi
}

# =============================================================================
# Container Information
# =============================================================================
is_container_running() {
    podman ps -a -f status=running -f name="^${CONTAINER_NAME}$" --format="{{.ID}}" | grep -q .
}

container_exists() {
    podman ps -a -f name="^${CONTAINER_NAME}$" --format="{{.ID}}" | grep -q .
}

show_container_state() {
    header "Container State"

    if is_container_running; then
        echo -e "Status:    ${GREEN}Running${NC}"
    elif container_exists; then
        echo -e "Status:    ${YELLOW}Stopped${NC}"
    else
        echo -e "Status:    ${RED}Not Found${NC}"
        return 1
    fi

    # Get container details
    local details
    details=$(podman inspect "$CONTAINER_NAME" 2>/dev/null) || return 1

    local state created started
    state=$(echo "$details" | podman inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
    created=$(echo "$details" | podman inspect --format '{{.Created}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
    started=$(echo "$details" | podman inspect --format '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")

    echo "Name:      $CONTAINER_NAME"
    echo "State:     $state"
    echo "Created:   $created"
    echo "Started:   $started"

    # Calculate uptime if running
    if is_container_running; then
        local uptime
        uptime=$(podman ps -f name="^${CONTAINER_NAME}$" --format "{{.Status}}" 2>/dev/null || echo "unknown")
        echo "Uptime:    $uptime"
    fi
}

show_port_mapping() {
    header "Port Mapping"

    local ports
    ports=$(podman port "$CONTAINER_NAME" 2>/dev/null) || {
        echo "No port mappings found"
        return 0
    }

    if [[ -z "$ports" ]]; then
        echo "No port mappings found"
    else
        echo "$ports"

        # Extract the S3 endpoint
        local s3_port
        s3_port=$(echo "$ports" | grep "7480" | head -1 | awk '{print $3}' | cut -d: -f2)
        if [[ -n "$s3_port" ]]; then
            echo ""
            echo -e "S3 Endpoint: ${GREEN}http://localhost:${s3_port}${NC}"
        fi
    fi
}

show_volume_mounts() {
    header "Volume Mounts"

    local mounts
    mounts=$(podman inspect --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' "$CONTAINER_NAME" 2>/dev/null) || {
        echo "No volume mounts found"
        return 0
    }

    if [[ -z "$mounts" ]]; then
        echo "No volume mounts found"
    else
        echo "$mounts"
    fi
}

show_disk_usage() {
    header "Disk Usage"

    local mounts
    mounts=$(podman inspect --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$CONTAINER_NAME" 2>/dev/null) || {
        echo "Could not determine volume paths"
        return 0
    }

    if [[ -z "$mounts" ]]; then
        echo "No volumes to check"
        return 0
    fi

    echo "$mounts" | while read -r mount_path; do
        if [[ -n "$mount_path" && -d "$mount_path" ]]; then
            local size
            size=$(du -sh "$mount_path" 2>/dev/null | cut -f1) || size="N/A"
            printf "%-50s %s\n" "$mount_path" "$size"
        fi
    done
}

show_recent_logs() {
    header "Recent Logs (last 10 lines)"

    podman logs --tail 10 "$CONTAINER_NAME" 2>&1 || {
        echo "Could not retrieve logs"
        return 0
    }
}

show_environment() {
    header "Environment Variables"

    podman inspect --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$CONTAINER_NAME" 2>/dev/null | \
        grep -E "^(COMPONENT|AWS_|RGW_)" || echo "No relevant environment variables found"
}

# =============================================================================
# Main
# =============================================================================
main() {
    debug "Starting $SCRIPT_NAME"
    debug "Container name: $CONTAINER_NAME"

    check_dependencies

    echo ""

    if ! show_container_state; then
        echo ""
        info "Container '$CONTAINER_NAME' does not exist"
        info "Start it with: ./bin/start-posix.sh"
        exit 0
    fi

    echo ""
    show_port_mapping
    echo ""
    show_volume_mounts

    if [[ "$VERBOSE" == true ]]; then
        echo ""
        show_disk_usage
        echo ""
        show_environment
    fi

    echo ""
    show_recent_logs
    echo ""
}

main
