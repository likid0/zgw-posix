# zgw-posix Helm Chart

## Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `quay.io/dparkes/zgw-posix` |
| `image.tag` | Container image tag | `latest` |
| `service.port` | Port exposed by the Service | `80` |
| `service.targetPort`| Port the container listens on | `7480` |
| `storage.size` | Size of the PVC | `20Gi` |
| `storage.storageClass` | Storage class for the PVC | `""` (default) |
| `storage.accessMode` | PVC Access Mode | `ReadWriteOnce` |
| `auth.accessKey` | S3 Access Key (auto base64-encoded by the chart) | `zippy` |
| `auth.secretKey` | S3 Secret Key (auto base64-encoded by the chart) | `zippy` |
| `openshift.enabled` | Enable OpenShift specific resources (SCC, Route) | `true` |
| `openshift.route.ssl.enabled` | Enable SSL for OpenShift Route | `true` |
