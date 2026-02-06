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
| `credentials.accessKey` | Base64 encoded S3 Access Key | `emlwcHk=` |
| `credentials.secretKey` | Base64 encoded S3 Secret Key | `emlwcHk=` |
| `openshift.enabled` | Enable OpenShift specific resources (SCC, Route) | `true` |
| `openshift.route.ssl.enabled` | Enable SSL for OpenShift Route | `true` |
