#FROM quay.io/ceph/ceph:v20.2
FROM quay.ceph.io/ceph-ci/ceph:wip-rgw-standalone
#FROM quay.ceph.io/ceph-ci/ceph-build:main.centos9.x86_64.default

USER root

# Install AWS CLI and s5cmd for in-container debugging
RUN dnf install -y awscli unzip \
    && dnf clean all \
    && S5CMD_VERSION="2.2.2" \
    && curl -sL "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/s5cmd_${S5CMD_VERSION}_Linux-64bit.tar.gz" \
       | tar xzf - -C /usr/local/bin s5cmd \
    && chmod +x /usr/local/bin/s5cmd

COPY ceph.conf /etc/ceph/ceph.conf
RUN chown ceph:ceph /etc/ceph/ceph.conf \
    && chown -R ceph:ceph /var/lib/ceph/radosgw

# Create home directory for ceph user
RUN mkdir -p /home/ceph/.aws \
    && chown -R ceph:ceph /home/ceph

ENV RGW_POSIX_BASE_PATH=/var/lib/ceph/rgw_posix_driver \
    RGW_POSIX_DATABASE_ROOT=/var/lib/ceph/rgw_posix_db \
    HOME=/home/ceph

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
