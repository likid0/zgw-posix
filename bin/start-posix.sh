#!/bin/bash
#
# start-posix.sh - Start the zgw-posix S3 gateway container
#
# Environment Variables:
#   ZGW_DATA_PATH     - Single parent directory for all data (default: ~/zgw-data)
#                       Contains: posix/, db/, store/ subdirectories
#   ZGW_POSIX_PORT    - Port to expose S3 API (default: 9090)
#   AWS_ACCESS_KEY_ID - S3 access key (default: zippy)
#   AWS_SECRET_ACCESS_KEY - S3 secret key (default: zippy)
#
# Usage: ./start-posix.sh [OPTIONS]
#
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
CONTAINER_NAME="zgw-posix"
DEFAULT_IMAGE="zgw-posix:latest"

# Single data directory with subdirectories
ZGW_DATA_PATH="${ZGW_DATA_PATH:-${HOME}/zgw-data}"
ZGW_POSIX_PORT="${ZGW_POSIX_PORT:-9090}"

# Credentials
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-zippy}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-zippy}"

# Script options
VERBOSE=false
DRY_RUN=false
FORCE=false
CUSTOM_NAME=""
CUSTOM_IMAGE=""
CUSTOM_DATA_PATH=""

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

Start the zgw-posix S3 gateway container.

Options:
  -h, --help          Show this help message and exit
  -v, --verbose       Enable verbose output
  -n, --dry-run       Show what would be done without executing
  -f, --force         Stop and replace running container
  -d, --data PATH     Data directory (default: ~/zgw-data)
  --name NAME         Custom container name (default: $CONTAINER_NAME)
  --image IMAGE       Custom image (default: $DEFAULT_IMAGE)

Environment Variables:
  ZGW_DATA_PATH       Single directory for all data (default: ~/zgw-data)
                      Subdirectories: posix/, db/, store/
  ZGW_POSIX_PORT      Port to expose S3 API (default: 9090)
  AWS_ACCESS_KEY_ID   S3 access key (default: zippy)
  AWS_SECRET_ACCESS_KEY  S3 secret key (default: zippy)

Directory Structure:
  <ZGW_DATA_PATH>/
  ├── posix/    S3 objects stored as files
  ├── db/       Metadata database (LMDB)
  └── store/    Backend store (users, policies)

Examples:
  # Start with defaults (uses ~/zgw-data)
  $SCRIPT_NAME

  # Start with custom data directory
  $SCRIPT_NAME -d /mnt/s3-storage

  # Start with custom port and verbose output
  ZGW_POSIX_PORT=8080 $SCRIPT_NAME -v

  # Force restart with custom image
  $SCRIPT_NAME --force --image quay.io/dparkes/zgw-posix:latest

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
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--data)
            CUSTOM_DATA_PATH="$2"
            shift 2
            ;;
        --name)
            CUSTOM_NAME="$2"
            shift 2
            ;;
        --image)
            CUSTOM_IMAGE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Apply custom options
[[ -n "$CUSTOM_NAME" ]] && CONTAINER_NAME="$CUSTOM_NAME"
[[ -n "$CUSTOM_IMAGE" ]] && DEFAULT_IMAGE="$CUSTOM_IMAGE"
[[ -n "$CUSTOM_DATA_PATH" ]] && ZGW_DATA_PATH="$CUSTOM_DATA_PATH"

# Derive subdirectory paths
ZGW_POSIX_PATH="${ZGW_DATA_PATH}/posix"
ZGW_DB_PATH="${ZGW_DATA_PATH}/db"
ZGW_STORE_PATH="${ZGW_DATA_PATH}/store"

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
# Directory Validation
# =============================================================================
validate_directories() {
    debug "Validating directories..."

    local dirs=("$ZGW_POSIX_PATH" "$ZGW_DB_PATH" "$ZGW_STORE_PATH")

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            debug "Creating directory: $dir"
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY-RUN] Would create directory: $dir"
            else
                mkdir -p "$dir" || {
                    error "Failed to create directory: $dir"
                    exit 1
                }
                info "Created directory: $dir"
            fi
        else
            debug "Directory exists: $dir"
        fi
    done

    # Note: After first run, directories may be owned by container's ceph user
    # (UID 167 mapped to host UID). Podman handles this with :Z flag.
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
    info "Stopping existing container: $CONTAINER_NAME"
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would stop and remove container: $CONTAINER_NAME"
    else
        podman kill "$CONTAINER_NAME" 2>/dev/null || true
        podman rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

start_container() {
    local cmd=(
        podman run
        --name "$CONTAINER_NAME"
        -v "${ZGW_POSIX_PATH}:/var/lib/ceph/rgw_posix_driver:rw,Z"
        -v "${ZGW_DB_PATH}:/var/lib/ceph/rgw_posix_db:rw,Z"
        -v "${ZGW_STORE_PATH}:/var/lib/ceph/radosgw:rw,Z"
        -e "COMPONENT=zgw-posix"
        -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
        -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        -e "RGW_POSIX_BASE_PATH=/var/lib/ceph/rgw_posix_driver"
        -e "RGW_POSIX_DATABASE_ROOT=/var/lib/ceph/rgw_posix_db"
        -p "${ZGW_POSIX_PORT}:7480"
        -d "$DEFAULT_IMAGE"
    )

    debug "Running command: ${cmd[*]}"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would execute:"
        echo "  ${cmd[*]}"
        return 0
    fi

    if "${cmd[@]}"; then
        info "Container started successfully"
        echo ""
        info "Connection Information:"
        echo "  Endpoint URL:    http://localhost:${ZGW_POSIX_PORT}"
        echo "  Access Key:      ${AWS_ACCESS_KEY_ID}"
        echo "  Secret Key:      ${AWS_SECRET_ACCESS_KEY}"
        echo ""
        info "Data Directory: ${ZGW_DATA_PATH}"
        echo "  posix/  -> S3 objects as files"
        echo "  db/     -> Metadata database"
        echo "  store/  -> Users and policies"
        echo ""
        info "Test with: aws --endpoint-url http://localhost:${ZGW_POSIX_PORT} s3 ls"
    else
        error "Failed to start container"
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    debug "Starting $SCRIPT_NAME"
    debug "Container name: $CONTAINER_NAME"
    debug "Image: $DEFAULT_IMAGE"
    debug "Data path: $ZGW_DATA_PATH"
    debug "Verbose: $VERBOSE"
    debug "Dry-run: $DRY_RUN"
    debug "Force: $FORCE"

    check_dependencies
    validate_directories

    if is_container_running; then
        if [[ "$FORCE" == true ]]; then
            warn "Container already running, forcing restart..."
            stop_container
        else
            error "Container '$CONTAINER_NAME' is already running"
            echo "Use --force to replace, or run stop-posix.sh first"
            exit 1
        fi
    elif container_exists; then
        debug "Removing stopped container: $CONTAINER_NAME"
        if [[ "$DRY_RUN" == false ]]; then
            podman rm "$CONTAINER_NAME" 2>/dev/null || true
        fi
    fi

    start_container
}

main
