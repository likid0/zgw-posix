# Z is for Zipper: S3 Gateway (POSIX)

zgw-posix is a lightweight S3 server based on the Ceph object gateway that stores objects directly on a POSIX filesystem. Access your data via S3 API or browse it as regular files.

The Ceph object gateway has conventionally carried the name radosgw, or rgw for short. [RADOS](https://ceph.com/assets/pdfs/weil-rados-pdsw07.pdf) is Ceph's native object storage system. Sans RADOS, the radosgw is the *zgw*.

This was made possible by the Zipper initiative, which introduced a layering API based on stackable modules/drivers, similar to Unix filesystems (VFS).

> This is a fork and cleanup of Kyle Bader's work in https://github.com/mmgaggle/zgw/tree/main

## Quick Start

A pre-built image is publicly available:

```
quay.io/dparkes/zgw-posix:latest
```

Choose your deployment method:

| Method | Best For | Guide |
|--------|----------|-------|
| [Podman / Docker](#podman-deployment) | Local development, single-node | Runs a container with local storage |
| [Helm Chart](#helm-chart-deployment) | Kubernetes / OpenShift | Deploys via `helm install` with a values file |
| [Deployment Manifest](#deployment-manifest) | Kubernetes / OpenShift (no Helm) | Single YAML manifest with `kubectl apply` |

### Try It in 30 Seconds (Podman)

```bash
# 1. Start the gateway (creates ~/zgw-data automatically)
./bin/start-posix.sh

# 2. Create a bucket and upload a file
AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy \
  aws --endpoint-url http://localhost:9090 s3 mb s3://mybucket

AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy \
  aws --endpoint-url http://localhost:9090 s3 cp /etc/hosts s3://mybucket/hosts

# 3. Verify the file exists on the filesystem
ls ~/zgw-data/posix/mybucket/
```

---

## Podman Deployment

### Prerequisites

- Podman or Docker installed
- AWS CLI (optional, for testing)

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ZGW_DATA_PATH` | `~/zgw-data` | Parent directory for all data (posix/, db/, store/) |
| `ZGW_POSIX_PORT` | `9090` | Port to expose S3 API |
| `AWS_ACCESS_KEY_ID` | `zippy` | S3 access key |
| `AWS_SECRET_ACCESS_KEY` | `zippy` | S3 secret key |

### Using Helper Scripts

The `bin/` directory contains helper scripts:

```bash
./bin/start-posix.sh       # Start the gateway
./bin/status-posix.sh      # Check status
./bin/restart-posix.sh     # Restart (preserves config)
./bin/stop-posix.sh        # Stop and remove
```

All scripts support common flags:

```bash
./bin/start-posix.sh --help      # Show usage
./bin/start-posix.sh --verbose   # Detailed output
./bin/start-posix.sh --dry-run   # Preview commands
```

Additional start options:

```bash
./bin/start-posix.sh --force                # Force replace running container
./bin/start-posix.sh -d /mnt/s3-storage     # Use custom data directory
./bin/start-posix.sh --image quay.io/dparkes/zgw-posix:latest  # Custom image
./bin/start-posix.sh --name my-s3-gateway   # Custom container name
```

### Configure AWS CLI

Add a profile to `~/.aws/credentials`:

```ini
[zgw]
aws_access_key_id = zippy
aws_secret_access_key = zippy
```

Use it with:

```bash
aws --profile zgw --endpoint-url http://localhost:9090 s3 ls
```

---

## Helm Chart Deployment

### Prerequisites

- Kubernetes or OpenShift cluster
- `helm` CLI (v3+)
- A StorageClass for persistent volumes

### Install

```bash
helm install zgw-posix examples/helm/zgw-posix \
  --namespace zgw --create-namespace \
  --set persistence.storageClassName=YOUR-STORAGE-CLASS
```

### Verify

```bash
kubectl -n zgw get pods -l app.kubernetes.io/name=zgw-posix
kubectl -n zgw wait --for=condition=ready pod -l app.kubernetes.io/name=zgw-posix --timeout=180s
```

### Uninstall

```bash
helm uninstall zgw-posix --namespace zgw
```

---

## Deployment Manifest

For clusters without Helm, use the raw Kubernetes/OpenShift manifest directly.

### Prerequisites

- Kubernetes or OpenShift cluster
- `kubectl` or `oc` CLI configured
- A StorageClass for persistent volumes

### Deploy on OpenShift

The manifest includes a dedicated ServiceAccount and SecurityContextConstraints (SCC) for the ceph user (UID 167), so no manual SCC grants are needed.

```bash
# Create a new project
oc new-project zgw

# Apply the manifest (set your storage class)
cat examples/openshift/zgw-posix.yaml | \
  sed 's/storage: 20Gi/storage: 20Gi\n  storageClassName: YOUR-STORAGE-CLASS/' | \
  oc apply -f -

# Wait for pod to be ready
oc wait --for=condition=ready pod -l app.kubernetes.io/name=zgw-posix --timeout=180s

# Verify the pod is using the zgw-posix-scc
oc get pod -l app.kubernetes.io/name=zgw-posix \
  -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'
```

### Deploy on Kubernetes

```bash
kubectl apply -f examples/openshift/zgw-posix.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zgw-posix
kubectl get pods -l app.kubernetes.io/name=zgw-posix
```

### What Gets Created

- **Secret**: S3 credentials (`zgw-posix-user`)
- **ConfigMap**: Ceph configuration
- **PVC**: Single persistent volume for all data (uses subPath mounts)
- **Deployment**: The zgw-posix container with resource limits and health probes
- **Service**: S3 API exposed at `http://s3-posix.<namespace>.svc.cluster.local`
- **Route**: External access via OpenShift router (HTTPS with TLS termination)

### External Access (OpenShift Route)

```bash
# Get the external S3 endpoint URL
oc get route s3-posix -o jsonpath='https://{.spec.host}'

# Example: https://s3-posix-zgw.apps.mycluster.example.com
```

Use the external URL with AWS CLI:

```bash
aws --endpoint-url https://s3-posix-zgw.apps.mycluster.example.com \
    --region default s3 ls
```

For Kubernetes clusters without OpenShift, uncomment the Ingress resource in the manifest and configure your domain.

### Test S3 Operations from the Cluster

```bash
# Create a bucket
oc run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=zippy" \
  --env="AWS_SECRET_ACCESS_KEY=zippy" \
  -- --endpoint-url http://s3-posix.zgw.svc.cluster.local \
     --region default s3 mb s3://test-bucket

# Upload a file
oc run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=zippy" \
  --env="AWS_SECRET_ACCESS_KEY=zippy" \
  -- --endpoint-url http://s3-posix.zgw.svc.cluster.local \
     --region default s3 cp /etc/hostname s3://test-bucket/hostname

# List bucket contents
oc run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=zippy" \
  --env="AWS_SECRET_ACCESS_KEY=zippy" \
  -- --endpoint-url http://s3-posix.zgw.svc.cluster.local \
     --region default s3 ls s3://test-bucket/

# Verify file on POSIX filesystem
oc exec deployment/zgw-posix -- ls -la /var/lib/ceph/rgw_posix_driver/test-bucket/
```

### Access from Within the Cluster

```bash
# Using s5cmd
s5cmd --endpoint-url http://s3-posix.<namespace>.svc.cluster.local mb s3://mybucket

# Using AWS CLI
aws --endpoint-url http://s3-posix.<namespace>.svc.cluster.local --region default s3 ls
```

### Using with Jupyter

Deploy a Jupyter notebook pre-configured with zgw-posix credentials:

```bash
# Ensure zgw-posix is running first
oc apply -f examples/openshift/zgw-notebook.yaml

# Port forward to access notebook
oc port-forward svc/jupyter 8888:80
```

Open http://localhost:8888 in your browser.

---

## Volume Architecture

The zgw-posix container uses a single data directory with three subdirectories:

```
HOST                              CONTAINER                           PURPOSE
~/zgw-data/
├── posix/  ───────────────────► /var/lib/ceph/rgw_posix_driver      S3 objects as files
├── db/     ───────────────────► /var/lib/ceph/rgw_posix_db          Metadata (LMDB)
└── store/  ───────────────────► /var/lib/ceph/radosgw               Users & policies
```

| Subdirectory | Container Path | Purpose | Size Guidance |
|--------------|----------------|---------|---------------|
| `posix/` | `/var/lib/ceph/rgw_posix_driver` | S3 objects stored as regular files | Size of your data |
| `db/` | `/var/lib/ceph/rgw_posix_db` | LMDB database for bucket/object metadata | ~1% of data size |
| `store/` | `/var/lib/ceph/radosgw` | DBStore for users, policies, configuration | 1-5 GB typical |

### SELinux and the :Z Flag

On SELinux-enabled systems (RHEL, Fedora, CentOS), the `:Z` flag is required for volume mounts:

```bash
-v ~/zgw-data/posix:/var/lib/ceph/rgw_posix_driver:rw,Z
```

The `:Z` option tells Podman to relabel the volume content with a private unshared label, allowing the container to read and write to the mounted directory.

---

## Building the Container

```bash
# Build with Docker
docker build -t zgw-posix docker/zgw-posix

# Or with Podman
podman build -t zgw-posix docker/zgw-posix
```
