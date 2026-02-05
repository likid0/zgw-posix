#!/bin/bash
#
# stop-posix.sh - Stop the zgw-posix S3 gateway container
#
# Usage: ./stop-posix.sh [OPTIONS]
#
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
CONTAINER_NAME="zgw-posix"

# Script options
VERBOSE=false
DRY_RUN=false
KEEP=false
TIMEOUT=10

# =============================================================================
# Colors
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
debug()   { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $*" || true; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Stop the zgw-posix S3 gateway container.

Options:
  -h, --help              Show this help message and exit
  -v, --verbose           Enable verbose output
  -n, --dry-run           Show what would be done without executing
  -k, --keep              Stop container but don't remove it
  -t, --timeout SECONDS   Graceful shutdown timeout (default: $TIMEOUT)
  --name NAME             Container name to stop (default: $CONTAINER_NAME)

Examples:
  # Stop and remove container
  $SCRIPT_NAME

  # Stop but keep container (can restart without recreation)
  $SCRIPT_NAME --keep

  # Stop with longer timeout for graceful shutdown
  $SCRIPT_NAME --timeout 30

  # Dry run to see what would happen
  $SCRIPT_NAME --dry-run

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
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -k|--keep)
            KEEP=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
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
    debug "Checking dependencies..."

    if ! command -v podman &> /dev/null; then
        error "podman is not installed or not in PATH"
        exit 1
    fi

    debug "podman found: $(command -v podman)"
}

# =============================================================================
# Container Management
# =============================================================================
is_container_running() {
    podman ps -a -f status=running -f name="^${CONTAINER_NAME}$" --format="{{.ID}}" | grep -q .
}

container_exists() {
    podman ps -a -f name="^${CONTAINER_NAME}$" --format="{{.ID}}" | grep -q .
}

stop_container() {
    debug "Attempting graceful stop with timeout: ${TIMEOUT}s"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would stop container: $CONTAINER_NAME (timeout: ${TIMEOUT}s)"
        return 0
    fi

    if podman stop --time "$TIMEOUT" "$CONTAINER_NAME" 2>/dev/null; then
        info "Container stopped gracefully"
    else
        warn "Graceful stop failed, forcing..."
        podman kill "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

remove_container() {
    if [[ "$KEEP" == true ]]; then
        debug "Keeping container (--keep flag set)"
        info "Container stopped but preserved. Use 'podman start $CONTAINER_NAME' to restart."
        return 0
    fi

    debug "Removing container: $CONTAINER_NAME"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would remove container: $CONTAINER_NAME"
        return 0
    fi

    if podman rm "$CONTAINER_NAME" 2>/dev/null; then
        info "Container removed"
    else
        warn "Failed to remove container"
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    debug "Starting $SCRIPT_NAME"
    debug "Container name: $CONTAINER_NAME"
    debug "Verbose: $VERBOSE"
    debug "Dry-run: $DRY_RUN"
    debug "Keep: $KEEP"
    debug "Timeout: $TIMEOUT"

    check_dependencies

    if is_container_running; then
        info "Stopping container: $CONTAINER_NAME"
        stop_container
        remove_container
        info "zgw-posix stopped successfully"
    elif container_exists; then
        warn "Container '$CONTAINER_NAME' exists but is not running"
        if [[ "$KEEP" == false ]]; then
            remove_container
        fi
    else
        warn "Container '$CONTAINER_NAME' does not exist"
        exit 0
    fi
}

main
