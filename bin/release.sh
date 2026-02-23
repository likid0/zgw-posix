#!/bin/bash
#
# release.sh - Build and push zgw-posix container image
#
# Usage:
#   ./bin/release.sh              # Push as :latest + :<timestamp> (e.g. 2025-09-07T16-13-09Z)
#   ./bin/release.sh v1.0.0       # Push as :latest + :v1.0.0
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
REGISTRY="${REGISTRY:-quay.io}"
IMAGE_NAME="${IMAGE_NAME:-dparkes/zgw-posix}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
VERSION="${1:-${TIMESTAMP}}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Check dependencies
command -v podman &>/dev/null || error "podman is required"

cd "$PROJECT_ROOT"

# Get git info
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git diff --quiet 2>/dev/null && echo "" || echo "-dirty")

info "Building zgw-posix"
info "  Version: ${VERSION}"
info "  Git:     ${GIT_SHA}${GIT_DIRTY}"
info "  Registry: ${REGISTRY}/${IMAGE_NAME}"
echo ""

# Build
info "Building container image..."
podman build -t zgw-posix:latest docker/zgw-posix

# Tag
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"

info "Tagging as ${FULL_IMAGE}:${VERSION}..."
podman tag zgw-posix:latest "${FULL_IMAGE}:${VERSION}"

info "Tagging as ${FULL_IMAGE}:latest..."
podman tag zgw-posix:latest "${FULL_IMAGE}:latest"

# Push both tags
info "Pushing ${FULL_IMAGE}:${VERSION}..."
podman push "${FULL_IMAGE}:${VERSION}"

info "Pushing ${FULL_IMAGE}:latest..."
podman push "${FULL_IMAGE}:latest"

echo ""
info "Release complete!"
echo "  Image: ${FULL_IMAGE}:${VERSION}"
echo "  Image: ${FULL_IMAGE}:latest"
echo "  Git:   ${GIT_SHA}${GIT_DIRTY}"
