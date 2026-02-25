#!/bin/bash
#
# start-posix.sh - Start the zgw-posix S3 gateway container
#
# Environment Variables:
#   ZGW_DATA_PATH         - Single parent directory for all data (default: ~/zgw-data)
#                           Contains: posix/, db/, store/, tls/ subdirectories
#   ZGW_POSIX_PORT        - Port to expose S3 API over HTTP (default: 9090)
#   ZGW_HTTPS_PORT        - Port to expose S3 API over HTTPS (default: 9443)
#   ZGW_TLS_ENABLED       - Enable HTTPS (default: false)
#   ZGW_TLS_CERT          - Path to TLS certificate file (auto-generated if not set)
#   ZGW_TLS_KEY           - Path to TLS private key file (auto-generated if not set)
#   AWS_ACCESS_KEY_ID     - S3 access key (default: zippy)
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
ZGW_HTTPS_PORT="${ZGW_HTTPS_PORT:-9443}"

# Credentials
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-zippy}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-zippy}"

# TLS options
ZGW_TLS_ENABLED="${ZGW_TLS_ENABLED:-false}"
ZGW_TLS_CERT="${ZGW_TLS_CERT:-}"
ZGW_TLS_KEY="${ZGW_TLS_KEY:-}"

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
  -h, --help            Show this help message and exit
  -v, --verbose         Enable verbose output
  -n, --dry-run         Show what would be done without executing
  -f, --force           Stop and replace running container
  -d, --data PATH       Data directory (default: ~/zgw-data)
  --name NAME           Custom container name (default: $CONTAINER_NAME)
  --image IMAGE         Custom image (default: $DEFAULT_IMAGE)
  --https               Enable HTTPS (auto-generates self-signed cert if needed)
  --cert PATH           Path to TLS certificate file (implies --https)
  --key  PATH           Path to TLS private key file (implies --https)
  --https-port PORT     HTTPS port (default: 9443)

Environment Variables:
  ZGW_DATA_PATH         Single directory for all data (default: ~/zgw-data)
                        Subdirectories: posix/, db/, store/, tls/
  ZGW_POSIX_PORT        HTTP port to expose S3 API (default: 9090)
  ZGW_HTTPS_PORT        HTTPS port to expose S3 API (default: 9443)
  ZGW_TLS_ENABLED       Enable HTTPS: true|false (default: false)
  ZGW_TLS_CERT          Path to TLS certificate file
  ZGW_TLS_KEY           Path to TLS private key file
  AWS_ACCESS_KEY_ID     S3 access key (default: zippy)
  AWS_SECRET_ACCESS_KEY S3 secret key (default: zippy)

Directory Structure:
  <ZGW_DATA_PATH>/
  ├── posix/    S3 objects stored as files
  ├── db/       Metadata database (LMDB)
  ├── store/    Backend store (users, policies)
  └── tls/      TLS certificates (auto-generated if --https and no --cert/--key)

Examples:
  # Start with defaults (HTTP only, uses ~/zgw-data)
  $SCRIPT_NAME

  # Start with HTTPS (auto-generates self-signed cert)
  $SCRIPT_NAME --https

  # Start with HTTPS using your own certificate
  $SCRIPT_NAME --https --cert /path/to/server.crt --key /path/to/server.key

  # Start with custom data directory and HTTPS
  $SCRIPT_NAME -d /mnt/s3-storage --https

  # Dry run to see what would happen
  $SCRIPT_NAME --dry-run --https

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
        --https)
            ZGW_TLS_ENABLED=true
            shift
            ;;
        --cert)
            ZGW_TLS_CERT="$2"
            ZGW_TLS_ENABLED=true
            shift 2
            ;;
        --key)
            ZGW_TLS_KEY="$2"
            ZGW_TLS_ENABLED=true
            shift 2
            ;;
        --https-port)
            ZGW_HTTPS_PORT="$2"
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
ZGW_TLS_DIR="${ZGW_DATA_PATH}/tls"

# =============================================================================
# Dependency Checks
# =============================================================================
check_dependencies() {
    debug "Checking dependencies..."

    if ! command -v podman &> /dev/null; then
        error "podman is not installed or not in PATH"
        exit 1
    fi

    if [[ "$ZGW_TLS_ENABLED" == "true" && -z "$ZGW_TLS_CERT" ]]; then
        if ! command -v openssl &> /dev/null; then
            error "openssl is required to generate a self-signed certificate (not found in PATH)"
            error "Either install openssl or provide --cert and --key"
            exit 1
        fi
    fi

    debug "podman found: $(command -v podman)"
}

# =============================================================================
# Directory Validation
# =============================================================================
validate_directories() {
    debug "Validating directories..."

    local dirs=("$ZGW_POSIX_PATH" "$ZGW_DB_PATH" "$ZGW_STORE_PATH")
    [[ "$ZGW_TLS_ENABLED" == "true" ]] && dirs+=("$ZGW_TLS_DIR")

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
}

# =============================================================================
# TLS Certificate Management
# =============================================================================
ensure_tls_cert() {
    [[ "$ZGW_TLS_ENABLED" != "true" ]] && return 0

    # Use provided cert/key if specified
    if [[ -n "$ZGW_TLS_CERT" && -n "$ZGW_TLS_KEY" ]]; then
        if [[ ! -f "$ZGW_TLS_CERT" ]]; then
            error "TLS certificate not found: $ZGW_TLS_CERT"
            exit 1
        fi
        if [[ ! -f "$ZGW_TLS_KEY" ]]; then
            error "TLS key not found: $ZGW_TLS_KEY"
            exit 1
        fi
        info "Using provided TLS certificate: $ZGW_TLS_CERT"
        return 0
    fi

    # Auto-generate self-signed cert into the tls/ data subdirectory
    local cert_file="${ZGW_TLS_DIR}/tls.crt"
    local key_file="${ZGW_TLS_DIR}/tls.key"

    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        info "Using existing self-signed TLS certificate: ${ZGW_TLS_DIR}/"
    else
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] Would generate self-signed TLS certificate in ${ZGW_TLS_DIR}/"
        else
            info "Generating self-signed TLS certificate in ${ZGW_TLS_DIR}/ ..."
            openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
                -keyout "$key_file" \
                -out "$cert_file" \
                -subj "/CN=zgw-posix" \
                -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
                2>/dev/null
            chmod 600 "$key_file"
            info "Self-signed certificate generated (valid 10 years)"
            warn "This is a self-signed certificate. S3 clients need --no-verify-ssl or equivalent."
        fi
    fi

    ZGW_TLS_CERT="$cert_file"
    ZGW_TLS_KEY="$key_file"
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
    )

    if [[ "$ZGW_TLS_ENABLED" == "true" ]]; then
        # Determine the host directory that contains the certs (for bind mount)
        local cert_host_dir
        cert_host_dir="$(dirname "${ZGW_TLS_CERT}")"
        local cert_container_dir="/etc/ceph/tls"

        cmd+=(
            -v "${cert_host_dir}:${cert_container_dir}:ro,Z"
            -e "RGW_TLS_ENABLED=true"
            -e "RGW_TLS_CERT_PATH=${cert_container_dir}/$(basename "${ZGW_TLS_CERT}")"
            -e "RGW_TLS_KEY_PATH=${cert_container_dir}/$(basename "${ZGW_TLS_KEY}")"
            -p "${ZGW_HTTPS_PORT}:7443"
        )
    fi

    cmd+=(-d "$DEFAULT_IMAGE")

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
        echo "  HTTP  Endpoint: http://localhost:${ZGW_POSIX_PORT}"
        if [[ "$ZGW_TLS_ENABLED" == "true" ]]; then
            echo "  HTTPS Endpoint: https://localhost:${ZGW_HTTPS_PORT}"
            warn "Self-signed cert: add --no-verify-ssl to aws CLI calls"
        fi
        echo "  Access Key:     ${AWS_ACCESS_KEY_ID}"
        echo "  Secret Key:     ${AWS_SECRET_ACCESS_KEY}"
        echo ""
        info "Data Directory: ${ZGW_DATA_PATH}"
        echo "  posix/  -> S3 objects as files"
        echo "  db/     -> Metadata database"
        echo "  store/  -> Users and policies"
        [[ "$ZGW_TLS_ENABLED" == "true" ]] && echo "  tls/    -> TLS certificates"
        echo ""
        info "Test with:"
        echo "  aws --endpoint-url http://localhost:${ZGW_POSIX_PORT} s3 ls"
        if [[ "$ZGW_TLS_ENABLED" == "true" ]]; then
            echo "  aws --endpoint-url https://localhost:${ZGW_HTTPS_PORT} --no-verify-ssl s3 ls"
        fi
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
    debug "TLS enabled: $ZGW_TLS_ENABLED"
    debug "Verbose: $VERBOSE"
    debug "Dry-run: $DRY_RUN"
    debug "Force: $FORCE"

    check_dependencies
    validate_directories
    ensure_tls_cert

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
