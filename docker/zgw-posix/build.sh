#!/bin/bash
# Build the ceph-ci image variant (full ceph CI image as base)
#
# Usage:
#   ./docker/zgw-posix/build.sh
#   IMAGE=zgw-posix:ceph-ci ./docker/zgw-posix/build.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-zgw-posix:latest}"
RUNTIME="${RUNTIME:-$(command -v podman || command -v docker)}"

echo "[build] variant : ceph-ci"
echo "[build] image   : ${IMAGE}"
echo "[build] context : ${SCRIPT_DIR}"
echo ""

"${RUNTIME}" build -t "${IMAGE}" "${SCRIPT_DIR}"
echo ""
echo "[build] done → ${IMAGE}"
