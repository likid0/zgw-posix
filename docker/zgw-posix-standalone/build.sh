#!/bin/bash
# Build the UBI9 + standalone RPM variant
#
# Usage:
#   ./docker/zgw-posix-standalone/build.sh
#   IMAGE=zgw-posix:latest ./docker/zgw-posix-standalone/build.sh
#
# Override the RPM URL at build time (the default is baked into the Dockerfile ARG):
#   RPM_URL=https://your-server/path/to/ceph-rgw-standalone-*.rpm \
#     ./docker/zgw-posix-standalone/build.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-zgw-posix:latest}"
RUNTIME="${RUNTIME:-$(command -v podman || command -v docker)}"

BUILD_ARGS=()
if [[ -n "${RPM_URL:-}" ]]; then
    BUILD_ARGS+=(--build-arg "RPM_URL=${RPM_URL}")
    echo "[build] RPM_URL : ${RPM_URL}"
fi

echo "[build] variant : ubi9-standalone"
echo "[build] image   : ${IMAGE}"
echo "[build] context : ${SCRIPT_DIR}"
echo ""

"${RUNTIME}" build "${BUILD_ARGS[@]}" -t "${IMAGE}" "${SCRIPT_DIR}"
echo ""
echo "[build] done → ${IMAGE}"
