#!/bin/bash

if [[ $(podman ps -a -f "status=running,name=zgw-posix" --format="{{.ID}}") ]] ; then
  echo "zgw-posix container already running"
else
  podman run --name zgw-posix \
           --user 167:167 \
           -p 7480:7480 \
           -v zgw-posix-driver:/var/lib/ceph/rgw_posix_driver \
           -v zgw-posix-db:/var/lib/ceph/rgw_posix_db \
           -e COMPONENT=zgw-posix \
           -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-zippy} \
           -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-zippy} \
           -e RGW_POSIX_BASE_PATH=/var/lib/ceph/rgw_posix_driver \
           -e RGW_POSIX_DATABASE_ROOT=/var/lib/ceph/rgw_posix_db \
           -dt quay.io/mmgaggle/zgw-posix:latest
fi
