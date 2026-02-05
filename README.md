# Z is for Zipper: S3 Gateway (POSIX)

zgw-posix is a lightweight S3 server based on the Ceph object gateway that stores objects directly on a POSIX filesystem. Access your data via S3 API or browse it as regular files.

The Ceph object gateway has conventionally carried the name radosgw, or rgw for short. [RADOS](https://ceph.com/assets/pdfs/weil-rados-pdsw07.pdf) is Ceph's native object storage system. Sans RADOS, the radosgw is the *zgw*.

This was made possible by the Zipper initiative, which introduced a layering API based on stackable modules/drivers, similar to Unix filesystems (VFS).

## Quick Start (Podman)

```bash
# 1. Start the gateway (creates ~/zgw-data automatically)
./bin/start-posix.sh

# 2. Test with AWS CLI
AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy \
  aws --endpoint-url http://localhost:9090 s3 mb s3://mybucket

AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy \
  aws --endpoint-url http://localhost:9090 s3 cp /etc/hosts s3://mybucket/hosts

# 3. Verify the file exists on the filesystem
ls ~/zgw-data/posix/mybucket/
```

## Understanding Directory Mapping

The zgw-posix container uses a single data directory with three subdirectories. This simplifies deployment - you only need one volume/PVC.

### Volume Architecture

```
HOST                              CONTAINER                           PURPOSE
~/zgw-data/
├── posix/  ───────────────────► /var/lib/ceph/rgw_posix_driver      S3 objects as files
├── db/     ───────────────────► /var/lib/ceph/rgw_posix_db          Metadata (LMDB)
└── store/  ───────────────────► /var/lib/ceph/radosgw               Users & policies
```

### Volume Details

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
The `:Z` option tells Podman to relabel the volume content with a private unshared label. This allows the container to read and write to the mounted directory.


## Podman Deployment

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ZGW_DATA_PATH` | `~/zgw-data` | Parent directory for all data (posix/, db/, store/) |
| `ZGW_POSIX_PORT` | `9090` | Port to expose S3 API |
| `AWS_ACCESS_KEY_ID` | `zippy` | S3 access key |
| `AWS_SECRET_ACCESS_KEY` | `zippy` | S3 secret key |

### Using Helper Scripts

The `bin/` directory contains helper scripts with consistent interfaces:

```bash
# Start the gateway
./bin/start-posix.sh

# Check status
./bin/status-posix.sh

# Restart (preserves config)
./bin/restart-posix.sh

# Stop and remove
./bin/stop-posix.sh
```

All scripts support common flags:

```bash
./bin/start-posix.sh --help      # Show usage
./bin/start-posix.sh --verbose   # Detailed output
./bin/start-posix.sh --dry-run   # Preview commands
```

Additional start options:

```bash
# Force replace running container
./bin/start-posix.sh --force

# Use custom data directory
./bin/start-posix.sh -d /mnt/s3-storage

# Use custom image
./bin/start-posix.sh --image quay.io/dparkes/zgw-posix:latest

# Custom container name
./bin/start-posix.sh --name my-s3-gateway
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

## Kubernetes/OpenShift Deployment

### Prerequisites

- Kubernetes cluster (minikube, OpenShift, etc.)
- `kubectl` or `oc` CLI configured to access your cluster
- A StorageClass for persistent volumes

### Deploy on OpenShift

The manifest includes a dedicated ServiceAccount and SecurityContextConstraints (SCC)
for the ceph user (UID 167), so no manual SCC grants are needed.

```bash
# Create a new project
oc new-project zgw

# Apply the manifest with your storage class
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
# Apply the manifest
kubectl apply -f examples/openshift/zgw-posix.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zgw-posix

# Check status
kubectl get pods -l app.kubernetes.io/name=zgw-posix
```

The manifest creates:
- **Secret**: S3 credentials (`zgw-posix-user`)
- **ConfigMap**: Ceph configuration
- **PVC**: Single persistent volume for all data (uses subPath mounts)
- **Deployment**: The zgw-posix container with resource limits and health probes
- **Service**: S3 API exposed at `http://s3-posix.<namespace>.svc.cluster.local`
- **Route**: External access via OpenShift router (HTTPS with TLS termination)

### External Access (OpenShift Route)

The manifest includes an OpenShift Route for external access:

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

Create a bucket:

```bash
oc run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=zippy" \
  --env="AWS_SECRET_ACCESS_KEY=zippy" \
  -- --endpoint-url http://s3-posix.zgw-test.svc.cluster.local \
     --region default s3 mb s3://test-bucket
```

Upload a file:

```bash
oc run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=zippy" \
  --env="AWS_SECRET_ACCESS_KEY=zippy" \
  -- --endpoint-url http://s3-posix.zgw-test.svc.cluster.local \
     --region default s3 cp /etc/hostname s3://test-bucket/hostname
```

List bucket contents:

```bash
oc run s3-test --rm -i --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=zippy" \
  --env="AWS_SECRET_ACCESS_KEY=zippy" \
  -- --endpoint-url http://s3-posix.zgw-test.svc.cluster.local \
     --region default s3 ls s3://test-bucket/
```

Verify file on POSIX filesystem:

```bash
oc exec deployment/zgw-posix -- ls -la /var/lib/ceph/rgw_posix_driver/test-bucket/
oc exec deployment/zgw-posix -- cat /var/lib/ceph/rgw_posix_driver/test-bucket/hostname
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

### Access from within the cluster

```bash
# Using s5cmd
s5cmd --endpoint-url http://s3-posix.<namespace>.svc.cluster.local mb s3://mybucket

# Using AWS CLI
aws --endpoint-url http://s3-posix.<namespace>.svc.cluster.local --region default s3 ls
```

## Building the Container

```bash
# Build the zgw-posix image
docker build -t zgw-posix docker/zgw-posix

# Or with podman
podman build -t zgw-posix docker/zgw-posix
```
