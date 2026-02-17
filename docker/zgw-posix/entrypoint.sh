#!/bin/bash
set -euo pipefail

# Default component if none supplied
COMPONENT=${COMPONENT:-zgw-posix}

# Writable config location (for OpenShift/restricted environments)
CEPH_CONF_DIR="/var/lib/ceph/radosgw"
CEPH_CONF="${CEPH_CONF_DIR}/ceph.conf"

########################################
# Helpers                              #
########################################
ensure_paths() {
  # Create POSIX driver directories so LMDB init won't abort
  mkdir -p "${RGW_POSIX_BASE_PATH}" \
           "${RGW_POSIX_DATABASE_ROOT}" \
           "${RGW_POSIX_DATABASE_ROOT}/rgw_posix_lmdbs" \
           "${CEPH_CONF_DIR}"
  chown -R ceph:ceph "${RGW_POSIX_BASE_PATH}" "${RGW_POSIX_DATABASE_ROOT}" "${CEPH_CONF_DIR}" 2>/dev/null || true
}

create_ceph_conf() {
  # Create ceph.conf in writable location with all required settings
  cat <<EOF > "${CEPH_CONF}"
[client]
    rgw backend store = posix
    rgw config store = dbstore
    rgw_posix_base_path = ${RGW_POSIX_BASE_PATH}
    rgw_posix_database_root = ${RGW_POSIX_DATABASE_ROOT}
EOF
  chown ceph:ceph "${CEPH_CONF}" 2>/dev/null || true
}

create_default_user() {
  ensure_paths
  create_ceph_conf

  if ! radosgw-admin -c "${CEPH_CONF}" user info --uid=zippy &>/dev/null; then
    # Don't fail container start if this command errors
    set +e
    radosgw-admin -c "${CEPH_CONF}" user create \
      --uid zippy \
      --display-name zippy \
      --access-key "${AWS_ACCESS_KEY_ID:-zippy}" \
      --secret-key "${AWS_SECRET_ACCESS_KEY:-zippy}"
    set -e
  fi

  # Fix ownership of LMDB files created by radosgw-admin (runs as root).
  # Without this, radosgw (running as ceph) cannot access the POSIX filter's
  # LMDB databases and the filter silently fails to load.
  chown -R ceph:ceph "${RGW_POSIX_BASE_PATH}" "${RGW_POSIX_DATABASE_ROOT}" 2>/dev/null || true
}

########################################
# Component dispatch                   #
########################################
case "${COMPONENT}" in
  zgw-posix|zgw-dbstore)
    create_default_user

    exec /usr/bin/radosgw \
      -c "${CEPH_CONF}" \
      --cluster ceph \
      --setuser ceph \
      --setgroup ceph \
      --default-log-to-stderr=true \
      --err-to-stderr=true \
      --default-log-to-file=false \
      --foreground \
      -n client.rgw \
      --no-mon-config
    ;;
  zgw-toolbox)
    echo "Toolbox container — sleeping indefinitely"
    exec sleep infinity
    ;;
  *)
    # Any other command: just run it
    exec "$@"
    ;;
esac
