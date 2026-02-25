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
aws --profile zgw --endpoint-url http://localhost:9090 s3 mb s3://mybucket
aws --profile zgw --endpoint-url http://localhost:9090 s3 cp /etc/hosts s3://mybucket/hosts

# 3. Verify the file exists on the filesystem
ls ~/zgw-data/posix/mybucket/
```

---

## S3 Credentials

All deployment methods use the same default credentials: **`zippy` / `zippy`**. There is a single S3 user (`zippy`) created at container startup. To use custom credentials, set them **before** the container starts — they cannot be changed at runtime without restarting.

### Podman / Docker

Set the environment variables before running the start script:

```bash
# Option 1: Export before starting
export AWS_ACCESS_KEY_ID=myaccesskey
export AWS_SECRET_ACCESS_KEY=mysecretkey
./bin/start-posix.sh

# Option 2: Inline
AWS_ACCESS_KEY_ID=myaccesskey AWS_SECRET_ACCESS_KEY=mysecretkey ./bin/start-posix.sh
```

Then configure your AWS CLI profile to match (see [Configure AWS CLI](#configure-aws-cli) below).

> **Note:** If you change credentials on a restart, the container automatically updates the stored keys to match. Existing data in `~/zgw-data` is preserved and accessible with the new credentials.

### Helm Chart (Kubernetes / OpenShift)

Pass credentials at install time:

```bash
helm install zgw-posix examples/helm/zgw-posix \
  --set auth.accessKey=myaccesskey \
  --set auth.secretKey=mysecretkey
```

The chart creates a Kubernetes Secret from these values automatically.

### Raw Manifest (Kubernetes / OpenShift)

Edit the Secret in `examples/openshift/zgw-posix.yaml` before applying. Generate base64 values:

```bash
echo -n 'myaccesskey' | base64   # replace ACCESS_KEY value in the Secret
echo -n 'mysecretkey' | base64   # replace SECRET_KEY value in the Secret
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
| `ZGW_POSIX_PORT` | `9090` | Port to expose S3 API over HTTP |
| `ZGW_HTTPS_PORT` | `9443` | Port to expose S3 API over HTTPS (requires `ZGW_TLS_ENABLED=true`) |
| `ZGW_TLS_ENABLED` | `false` | Enable HTTPS on the gateway |
| `ZGW_TLS_CERT` | _(auto-generated)_ | Path to TLS certificate file; auto-generates self-signed if not set |
| `ZGW_TLS_KEY` | _(auto-generated)_ | Path to TLS private key file |
| `AWS_ACCESS_KEY_ID` | `zippy` | S3 access key (see [S3 Credentials](#s3-credentials)) |
| `AWS_SECRET_ACCESS_KEY` | `zippy` | S3 secret key (see [S3 Credentials](#s3-credentials)) |

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

### HTTPS (TLS)

Enable HTTPS with a self-signed certificate (auto-generated on first run, reused on restart):

```bash
./bin/start-posix.sh --https
```

S3 clients need `--no-verify-ssl` for self-signed certificates:

```bash
aws --endpoint-url https://localhost:9443 --no-verify-ssl --region default s3 ls
```

Use your own certificate:

```bash
./bin/start-posix.sh --https --cert /path/to/server.crt --key /path/to/server.key
```

HTTP (port 9090) and HTTPS (port 9443) run simultaneously. The self-signed certificate is stored in `$ZGW_DATA_PATH/tls/` and is valid for 10 years.

### Configure AWS CLI

Add a profile to `~/.aws/config` and `~/.aws/credentials` matching your S3 credentials:

```ini
# ~/.aws/credentials
[zgw]
aws_access_key_id = zippy
aws_secret_access_key = zippy
```

```ini
# ~/.aws/config
[profile zgw]
region = default
output = json
```

If you set custom credentials (see [S3 Credentials](#s3-credentials)), update the credentials file to match.

> **Note:** The `region` setting is required by the AWS CLI even though zgw-posix ignores it. Without it you'll get `argument of type 'NoneType' is not iterable`.

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

To use custom S3 credentials, see [S3 Credentials](#s3-credentials).

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

To use custom S3 credentials, see [S3 Credentials](#s3-credentials).

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
- **Service**: S3 API exposed at `http://s3-posix.<namespace>.svc.cluster.local` (HTTP port 80); port 443 added when pod-level TLS is enabled
- **Route**: External access via OpenShift router (edge TLS termination by default; passthrough when pod-level TLS is enabled)

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

### Pod-level TLS (HTTPS at the RGW pod, passthrough route)

By default the Route terminates TLS at the OpenShift router (edge). To terminate TLS inside the pod instead — so traffic is encrypted end-to-end — enable pod-level TLS via the Helm chart:

**Option A — OpenShift service serving certificate (recommended for OCP, no cert-manager needed):**

```bash
helm install zgw-posix examples/helm/zgw-posix \
  --namespace zgw \
  --set podTLS.enabled=true \
  --set podTLS.openshiftServingCert=true
```

OCP automatically issues a cluster-signed certificate for `CN=s3-posix.<namespace>.svc` and injects it into the pod. The Route is reconfigured to use `passthrough` termination.

**Option B — Bring your own TLS secret (cert-manager or manual):**

```bash
# Create a TLS secret first (e.g. from cert-manager or manually)
kubectl create secret tls zgw-posix-tls --cert=server.crt --key=server.key -n zgw

helm install zgw-posix examples/helm/zgw-posix \
  --namespace zgw \
  --set podTLS.enabled=true \
  --set podTLS.existingSecret=zgw-posix-tls
```

When pod-level TLS is enabled the Service exposes both port 80 (HTTP) and port 443 (HTTPS). Internal consumers can reach the HTTPS endpoint at:

```
https://s3-posix.<namespace>.svc.cluster.local
```

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
