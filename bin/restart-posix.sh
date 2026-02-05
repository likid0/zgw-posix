#!/bin/bash
#
# restart-posix.sh - Restart the zgw-posix S3 gateway container
#
# Preserves configuration by reusing environment variables and volume mounts.
#
# Usage: ./restart-posix.sh [OPTIONS]
#
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="zgw-posix"

# Script options
VERBOSE=false
DRY_RUN=false

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

Restart the zgw-posix S3 gateway container.

This script stops the running container and starts a new one with the same
configuration (environment variables and volume mounts are preserved via
the start-posix.sh script).

Options:
  -h, --help          Show this help message and exit
  -v, --verbose       Enable verbose output
  -n, --dry-run       Show what would be done without executing
  --name NAME         Container name (default: $CONTAINER_NAME)

Examples:
  # Restart container
  $SCRIPT_NAME

  # Restart with verbose output
  $SCRIPT_NAME -v

  # Dry run to see what would happen
  $SCRIPT_NAME --dry-run

EOF
    exit 0
}

# =============================================================================
# Argument Parsing
# =============================================================================
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -v|--verbose)
            VERBOSE=true
            EXTRA_ARGS+=("--verbose")
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            EXTRA_ARGS+=("--dry-run")
            shift
            ;;
        --name)
            CONTAINER_NAME="$2"
            EXTRA_ARGS+=("--name" "$2")
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

    if [[ ! -x "${SCRIPT_DIR}/stop-posix.sh" ]]; then
        error "stop-posix.sh not found or not executable in ${SCRIPT_DIR}"
        exit 1
    fi

    if [[ ! -x "${SCRIPT_DIR}/start-posix.sh" ]]; then
        error "start-posix.sh not found or not executable in ${SCRIPT_DIR}"
        exit 1
    fi

    debug "All dependencies found"
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

# =============================================================================
# Main
# =============================================================================
main() {
    debug "Starting $SCRIPT_NAME"
    debug "Container name: $CONTAINER_NAME"
    debug "Verbose: $VERBOSE"
    debug "Dry-run: $DRY_RUN"

    check_dependencies

    if is_container_running; then
        info "Stopping container: $CONTAINER_NAME"
        "${SCRIPT_DIR}/stop-posix.sh" "${EXTRA_ARGS[@]}" --name "$CONTAINER_NAME"
    elif container_exists; then
        warn "Container exists but is not running, cleaning up..."
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] Would remove stopped container: $CONTAINER_NAME"
        else
            podman rm "$CONTAINER_NAME" 2>/dev/null || true
        fi
    else
        warn "Container '$CONTAINER_NAME' was not running"
    fi

    info "Starting container: $CONTAINER_NAME"
    "${SCRIPT_DIR}/start-posix.sh" "${EXTRA_ARGS[@]}" --name "$CONTAINER_NAME"

    info "Restart complete"
}

main
