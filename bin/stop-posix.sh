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

VERBOSE=false
DRY_RUN=false
KEEP=false
PURGE_VOLUMES=false
TIMEOUT=10
CUSTOM_NAME=""

# =============================================================================
# Colors
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

Stop the zgw-posix S3 gateway container (Podman or Docker).

Options:
  -h, --help              Show this help message and exit
  -v, --verbose           Enable verbose output
  -n, --dry-run           Show what would be done without executing
  -k, --keep              Stop container but don't remove it
  -t, --timeout SECONDS   Graceful shutdown timeout (default: $TIMEOUT)
  --name NAME             Container name to stop (default: $CONTAINER_NAME)
  --purge-volumes         Also remove the named volumes (deletes all data)

Examples:
  # Stop and remove container
  $SCRIPT_NAME

  # Stop but keep container (can restart without recreation)
  $SCRIPT_NAME --keep

  # Stop with longer timeout for graceful shutdown
  $SCRIPT_NAME --timeout 30

  # Stop and delete all stored data
  $SCRIPT_NAME --purge-volumes

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
        -h|--help)        usage ;;
        -v|--verbose)     VERBOSE=true;       shift ;;
        -n|--dry-run)     DRY_RUN=true;       shift ;;
        -k|--keep)        KEEP=true;          shift ;;
        -t|--timeout)     TIMEOUT="$2";       shift 2 ;;
        --name)           CUSTOM_NAME="$2";   shift 2 ;;
        --purge-volumes)  PURGE_VOLUMES=true; shift ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

[[ -n "$CUSTOM_NAME" ]] && CONTAINER_NAME="$CUSTOM_NAME"

# Named volume names — derived from container name (mirrors start-posix.sh)
VOL_POSIX="${CONTAINER_NAME}-posix"
VOL_DB="${CONTAINER_NAME}-db"
VOL_STORE="${CONTAINER_NAME}-store"

# =============================================================================
# Runtime Detection
# =============================================================================
detect_runtime() {
    if command -v podman &>/dev/null; then
        RUNTIME="podman"
    elif command -v docker &>/dev/null; then
        RUNTIME="docker"
    else
        error "Neither podman nor docker found in PATH"
        exit 1
    fi
    debug "Container runtime: $RUNTIME"
}

# =============================================================================
# Container Management
# =============================================================================
is_container_running() {
    $RUNTIME ps -a -f status=running -f name="^${CONTAINER_NAME}$" --format="{{.ID}}" | grep -q .
}

container_exists() {
    $RUNTIME ps -a -f name="^${CONTAINER_NAME}$" --format="{{.ID}}" | grep -q .
}

stop_container() {
    debug "Attempting graceful stop with timeout: ${TIMEOUT}s"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would stop container: $CONTAINER_NAME (timeout: ${TIMEOUT}s)"
        return 0
    fi

    if $RUNTIME stop --time "$TIMEOUT" "$CONTAINER_NAME" 2>/dev/null; then
        info "Container stopped gracefully"
    else
        warn "Graceful stop failed, forcing..."
        $RUNTIME kill "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

remove_container() {
    if [[ "$KEEP" == true ]]; then
        debug "Keeping container (--keep flag set)"
        info "Container stopped but preserved. Use '$RUNTIME start $CONTAINER_NAME' to restart."
        return 0
    fi

    debug "Removing container: $CONTAINER_NAME"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would remove container: $CONTAINER_NAME"
        return 0
    fi

    if $RUNTIME rm "$CONTAINER_NAME" 2>/dev/null; then
        info "Container removed"
    else
        warn "Failed to remove container"
    fi
}

purge_volumes() {
    info "Removing named volumes (all stored data will be lost)..."
    for vol in "$VOL_POSIX" "$VOL_DB" "$VOL_STORE"; do
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] Would remove volume: $vol"
        else
            $RUNTIME volume rm "$vol" 2>/dev/null && info "Removed volume: $vol" || true
        fi
    done
}

# =============================================================================
# Main
# =============================================================================
main() {
    detect_runtime

    debug "Container: $CONTAINER_NAME  Runtime: $RUNTIME"
    debug "Verbose: $VERBOSE  Dry-run: $DRY_RUN  Keep: $KEEP  Timeout: $TIMEOUT"

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
    fi

    if [[ "$PURGE_VOLUMES" == true ]]; then
        purge_volumes
    fi
}

main
