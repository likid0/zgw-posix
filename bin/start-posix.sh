#!/bin/bash
#
# start-posix.sh - Start the zgw-posix S3 gateway container
#
# Uses named volumes for all persistent data so the script works identically
# on Linux and macOS (Podman or Docker). Named volumes are managed by the
# container runtime and avoid APFS/bind-mount permission issues on macOS.
#
# Environment Variables:
#   ZGW_POSIX_PORT        - Port to expose S3 API over HTTP (default: 9090)
#   ZGW_HTTPS_PORT        - Port to expose S3 API over HTTPS (default: 9443)
#   ZGW_TLS_ENABLED       - Enable HTTPS (default: false)
#   ZGW_TLS_CERT          - Path to TLS certificate file (auto-generated if not set)
#   ZGW_TLS_KEY           - Path to TLS private key file (auto-generated if not set)
#   ZGW_TLS_DIR           - Directory for auto-generated TLS certs (default: ~/.zgw-posix/tls)
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

ZGW_POSIX_PORT="${ZGW_POSIX_PORT:-9090}"
ZGW_HTTPS_PORT="${ZGW_HTTPS_PORT:-9443}"

AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-zippy}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-zippy}"

ZGW_TLS_ENABLED="${ZGW_TLS_ENABLED:-false}"
ZGW_TLS_CERT="${ZGW_TLS_CERT:-}"
ZGW_TLS_KEY="${ZGW_TLS_KEY:-}"
ZGW_TLS_DIR="${ZGW_TLS_DIR:-${HOME}/.zgw-posix/tls}"

VERBOSE=false
DRY_RUN=false
FORCE=false
CUSTOM_NAME=""
CUSTOM_IMAGE=""

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

Start the zgw-posix S3 gateway container (Podman or Docker).

Data is stored in named volumes managed by the container runtime —
works identically on Linux and macOS without bind-mount permission issues.

Options:
  -h, --help            Show this help message and exit
  -v, --verbose         Enable verbose output
  -n, --dry-run         Show what would be done without executing
  -f, --force           Stop and replace running container
  --name NAME           Custom container name (default: $CONTAINER_NAME)
  --image IMAGE         Custom image (default: $DEFAULT_IMAGE)
  --https               Enable HTTPS (auto-generates self-signed cert if needed)
  --cert PATH           Path to TLS certificate file (implies --https)
  --key  PATH           Path to TLS private key file (implies --https)
  --https-port PORT     HTTPS port (default: 9443)

Environment Variables:
  ZGW_POSIX_PORT        HTTP port to expose S3 API (default: 9090)
  ZGW_HTTPS_PORT        HTTPS port to expose S3 API (default: 9443)
  ZGW_TLS_ENABLED       Enable HTTPS: true|false (default: false)
  ZGW_TLS_CERT          Path to TLS certificate file
  ZGW_TLS_KEY           Path to TLS private key file
  ZGW_TLS_DIR           Directory for auto-generated TLS certs (default: ~/.zgw-posix/tls)
  AWS_ACCESS_KEY_ID     S3 access key (default: zippy)
  AWS_SECRET_ACCESS_KEY S3 secret key (default: zippy)

Named Volumes (created automatically, named after the container):
  <name>-posix   S3 objects stored as files
  <name>-db      Metadata database (LMDB)
  <name>-store   Backend store (users, policies)

Examples:
  # Start with defaults (HTTP only)
  $SCRIPT_NAME

  # Start with HTTPS (auto-generates self-signed cert)
  $SCRIPT_NAME --https

  # Start with HTTPS using your own certificate
  $SCRIPT_NAME --https --cert /path/to/server.crt --key /path/to/server.key

  # Force restart
  $SCRIPT_NAME --force

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
        -h|--help)        usage ;;
        -v|--verbose)     VERBOSE=true;           shift ;;
        -n|--dry-run)     DRY_RUN=true;           shift ;;
        -f|--force)       FORCE=true;             shift ;;
        --name)           CUSTOM_NAME="$2";       shift 2 ;;
        --image)          CUSTOM_IMAGE="$2";      shift 2 ;;
        --https)          ZGW_TLS_ENABLED=true;   shift ;;
        --cert)           ZGW_TLS_CERT="$2"; ZGW_TLS_ENABLED=true; shift 2 ;;
        --key)            ZGW_TLS_KEY="$2";  ZGW_TLS_ENABLED=true; shift 2 ;;
        --https-port)     ZGW_HTTPS_PORT="$2";    shift 2 ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

[[ -n "$CUSTOM_NAME" ]]  && CONTAINER_NAME="$CUSTOM_NAME"
[[ -n "$CUSTOM_IMAGE" ]] && DEFAULT_IMAGE="$CUSTOM_IMAGE"

# Named volume names — derived from container name so multiple instances don't clash
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
# Dependency Checks
# =============================================================================
check_dependencies() {
    detect_runtime

    if [[ "$ZGW_TLS_ENABLED" == "true" && -z "$ZGW_TLS_CERT" ]]; then
        if ! command -v openssl &>/dev/null; then
            error "openssl is required to generate a self-signed certificate (not found in PATH)"
            error "Either install openssl or provide --cert and --key"
            exit 1
        fi
    fi
}

# =============================================================================
# Volume Management
# =============================================================================
ensure_volumes() {
    for vol in "$VOL_POSIX" "$VOL_DB" "$VOL_STORE"; do
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] Would create volume: $vol"
        else
            $RUNTIME volume create "$vol" 2>/dev/null || true
            debug "Volume ready: $vol"
        fi
    done
}

# =============================================================================
# TLS Certificate Management
# =============================================================================
ensure_tls_cert() {
    [[ "$ZGW_TLS_ENABLED" != "true" ]] && return 0

    if [[ -n "$ZGW_TLS_CERT" && -n "$ZGW_TLS_KEY" ]]; then
        [[ ! -f "$ZGW_TLS_CERT" ]] && { error "TLS certificate not found: $ZGW_TLS_CERT"; exit 1; }
        [[ ! -f "$ZGW_TLS_KEY" ]]  && { error "TLS key not found: $ZGW_TLS_KEY"; exit 1; }
        info "Using provided TLS certificate: $ZGW_TLS_CERT"
        return 0
    fi

    local cert_file="${ZGW_TLS_DIR}/tls.crt"
    local key_file="${ZGW_TLS_DIR}/tls.key"

    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        info "Using existing self-signed TLS certificate: ${ZGW_TLS_DIR}/"
    else
        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY-RUN] Would generate self-signed TLS certificate in ${ZGW_TLS_DIR}/"
        else
            mkdir -p "$ZGW_TLS_DIR"
            info "Generating self-signed TLS certificate in ${ZGW_TLS_DIR}/ ..."
            openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
                -keyout "$key_file" \
                -out "$cert_file" \
                -subj "/CN=zgw-posix" \
                -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
                2>/dev/null
            chmod 600 "$key_file"
            info "Self-signed certificate generated (valid 10 years)"
            warn "Self-signed cert — S3 clients need --no-verify-ssl or equivalent."
        fi
    fi

    ZGW_TLS_CERT="$cert_file"
    ZGW_TLS_KEY="$key_file"
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
    info "Stopping existing container: $CONTAINER_NAME"
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would stop and remove container: $CONTAINER_NAME"
    else
        $RUNTIME kill "$CONTAINER_NAME" 2>/dev/null || true
        $RUNTIME rm   "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

start_container() {
    local cmd=(
        $RUNTIME run
        --name "$CONTAINER_NAME"
        --privileged
        -v "${VOL_POSIX}:/var/lib/ceph/rgw_posix_driver:rw"
        -v "${VOL_DB}:/var/lib/ceph/rgw_posix_db:rw"
        -v "${VOL_STORE}:/var/lib/ceph/radosgw:rw"
        -e "COMPONENT=zgw-posix"
        -e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
        -e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        -e "RGW_POSIX_BASE_PATH=/var/lib/ceph/rgw_posix_driver"
        -e "RGW_POSIX_DATABASE_ROOT=/var/lib/ceph/rgw_posix_db"
        -p "${ZGW_POSIX_PORT}:7480"
    )

    if [[ "$ZGW_TLS_ENABLED" == "true" ]]; then
        local cert_host_dir cert_container_dir="/etc/ceph/tls"
        cert_host_dir="$(dirname "${ZGW_TLS_CERT}")"
        cmd+=(
            -v "${cert_host_dir}:${cert_container_dir}:ro"
            -e "RGW_TLS_ENABLED=true"
            -e "RGW_TLS_CERT_PATH=${cert_container_dir}/$(basename "${ZGW_TLS_CERT}")"
            -e "RGW_TLS_KEY_PATH=${cert_container_dir}/$(basename "${ZGW_TLS_KEY}")"
            -p "${ZGW_HTTPS_PORT}:7443"
        )
    fi

    cmd+=(-d "$DEFAULT_IMAGE")

    debug "Running: ${cmd[*]}"

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
        info "Named Volumes (runtime: $RUNTIME):"
        echo "  ${VOL_POSIX}  -> S3 objects as files"
        echo "  ${VOL_DB}     -> Metadata database"
        echo "  ${VOL_STORE}  -> Users and policies"
        echo ""
        echo "  Inspect: $RUNTIME volume inspect ${VOL_POSIX}"
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
    debug "Container: $CONTAINER_NAME  Image: $DEFAULT_IMAGE  TLS: $ZGW_TLS_ENABLED"

    check_dependencies
    ensure_volumes
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
        [[ "$DRY_RUN" == false ]] && $RUNTIME rm "$CONTAINER_NAME" 2>/dev/null || true
    fi

    start_container
}

main
