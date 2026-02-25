# zgw-posix Helm Chart

## Configuration Options

### Image & Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `quay.io/dparkes/zgw-posix` |
| `image.tag` | Container image tag | `latest` |
| `service.port` | HTTP port exposed by the Service | `80` |
| `service.targetPort` | HTTP port the container listens on | `7480` |

### Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storage.size` | Size of the PVC | `20Gi` |
| `storage.storageClass` | Storage class for the PVC | `""` (cluster default) |
| `storage.accessMode` | PVC access mode | `ReadWriteOnce` |

### Credentials

| Parameter | Description | Default |
|-----------|-------------|---------|
| `auth.accessKey` | S3 access key (auto base64-encoded) | `zippy` |
| `auth.secretKey` | S3 secret key (auto base64-encoded) | `zippy` |

### OpenShift

| Parameter | Description | Default |
|-----------|-------------|---------|
| `openshift.enabled` | Enable OpenShift resources (SCC, Route) | `true` |
| `openshift.route.termination` | Route TLS termination: `edge` or `passthrough` | `edge` |

### Pod-level TLS

Enable HTTPS directly on the RGW pod (port 7443). The Service gains a port 443 entry and the Route switches to `passthrough` termination automatically.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podTLS.enabled` | Enable HTTPS at the pod (RGW listens on 7443) | `false` |
| `podTLS.openshiftServingCert` | Let OCP auto-generate a cluster-signed cert (OCP only) | `false` |
| `podTLS.existingSecret` | Name of an existing TLS secret (`tls.crt` / `tls.key`) | `""` |

`openshiftServingCert` and `existingSecret` are mutually exclusive. `openshiftServingCert` takes precedence.

**OCP serving certificate (zero cert management):**

```bash
helm install zgw-posix examples/helm/zgw-posix \
  --set podTLS.enabled=true \
  --set podTLS.openshiftServingCert=true
```

**Bring your own secret (cert-manager or manual):**

```bash
helm install zgw-posix examples/helm/zgw-posix \
  --set podTLS.enabled=true \
  --set podTLS.existingSecret=my-tls-secret
```

### Quotas

Applied to the default S3 user via `radosgw-admin quota set` at container startup. Sizes accept unit suffixes (e.g. `50G`, `1T`). Use `-1` for unlimited object counts.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `quotas.user.enabled` | Enable per-user quota (total across all buckets) | `false` |
| `quotas.user.maxSize` | Max total storage (e.g. `"50G"`) | `""` |
| `quotas.user.maxObjects` | Max total object count | `""` |
| `quotas.bucket.enabled` | Enable per-bucket quota | `false` |
| `quotas.bucket.maxSize` | Max storage per bucket (e.g. `"10G"`) | `""` |
| `quotas.bucket.maxObjects` | Max objects per bucket | `""` |

### Kubernetes Ingress

For non-OpenShift deployments. When `podTLS.enabled` is also set, the `ssl-passthrough` annotation is added automatically.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Create a Kubernetes Ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Additional ingress annotations | `{}` |
| `ingress.hosts` | List of host rules (`host`, `paths[].path`, `paths[].pathType`) | `[]` |
| `ingress.tls` | TLS configuration (`secretName`, `hosts`) — ignored when `podTLS.enabled` | `[]` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `256Mi` |
| `resources.limits.cpu` | CPU limit | `2000m` |
| `resources.limits.memory` | Memory limit | `2Gi` |
