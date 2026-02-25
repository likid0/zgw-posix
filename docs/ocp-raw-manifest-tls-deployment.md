# Deploying zgw-posix with Pod-Level TLS via Raw OCP Manifest

---

## Prerequisites

- OpenShift cluster with `oc` configured
- A namespace (we use `zgw`)

```bash
oc new-project zgw
```

---

## Step 1: Remove any existing Helm release

If zgw-posix was previously deployed via Helm, uninstall it first:

```bash
helm uninstall zgw-posix -n zgw
```

---

## Step 2: Prepare the manifest

Start from `examples/openshift/zgw-posix.yaml`. The TLS-enabled version used
here has the following `[TLS]` blocks uncommented relative to the base file:

**Service** — OCP serving cert annotation + port 443:
```yaml
metadata:
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: zgw-posix-serving-cert
spec:
  ports:
    - port: 443
      targetPort: 7443
      name: s3-https
```

**Deployment** — port 7443, TLS env vars, volumeMount:
```yaml
ports:
  - containerPort: 7443
    name: s3-https
env:
  - name: RGW_TLS_ENABLED
    value: "true"
  - name: RGW_TLS_CERT_PATH
    value: /etc/ceph/tls/tls.crt
  - name: RGW_TLS_KEY_PATH
    value: /etc/ceph/tls/tls.key
volumeMounts:
  - mountPath: /etc/ceph/tls
    name: tls-certs
    readOnly: true
volumes:
  - name: tls-certs
    secret:
      secretName: zgw-posix-serving-cert
```

**Probes** — switched from `httpGet`/`tcpSocket port 7480` to `tcpSocket port s3-https`.

**Route** — passthrough instead of edge:
```yaml
port:
  targetPort: s3-https
tls:
  termination: passthrough
  insecureEdgeTerminationPolicy: Redirect
```

The full ready-to-apply TLS manifest is at `/tmp/zgw-posix-tls.yaml` (generated
during this test session; copy it to the repo if you want to keep it).

---

## Step 3: Apply the manifest

```bash
oc apply -f /tmp/zgw-posix-tls.yaml -n zgw
```

Output:
```
serviceaccount/zgw-posix-sa created
securitycontextconstraints.security.openshift.io/zgw-posix-scc created
clusterrole.rbac.authorization.k8s.io/zgw-posix-scc-role created
rolebinding.rbac.authorization.k8s.io/zgw-posix-scc-binding created
secret/zgw-posix-user created
configmap/zgw-posix-cm created
persistentvolumeclaim/zgw-posix-data created
deployment.apps/zgw-posix created
service/s3-posix created
route.route.openshift.io/s3-posix created
```

---

## Step 4: OCP auto-issues the TLS certificate

Because of the Service annotation, OCP's service serving certificate controller
immediately creates the secret `zgw-posix-serving-cert` in the namespace:

```bash
oc get secret zgw-posix-serving-cert -n zgw
# NAME                     TYPE                DATA   AGE
# zgw-posix-serving-cert   kubernetes.io/tls   2      12s
```

The cert is cluster-signed with `CN=s3-posix.zgw.svc` and valid for 2 years.
No cert-manager or manual CSR required.

---

## Step 5: Wait for pod ready

```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/name=zgw-posix -n zgw --timeout=180s
# pod/zgw-posix-58f6b4dbcc-d4qtc condition met
```

---

## Step 6: Verify TLS — external route

```bash
ROUTE=$(oc get route s3-posix -n zgw -o jsonpath='{.spec.host}')

openssl s_client -connect ${ROUTE}:443 -servername ${ROUTE} </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Output:
```
subject=CN=s3-posix.zgw.svc
issuer=CN=openshift-service-serving-signer@1768293776
notBefore=Feb 25 13:05:11 2026 GMT
notAfter=Feb 25 13:05:12 2028 GMT
```

---

## Step 7: Verify TLS — internal Service

```bash
oc exec -n zgw deployment/zgw-posix -- \
  openssl s_client -connect s3-posix.zgw.svc.cluster.local:443 \
    -servername s3-posix.zgw.svc.cluster.local </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Output:
```
subject=CN=s3-posix.zgw.svc
issuer=CN=openshift-service-serving-signer@1768293776
notBefore=Feb 25 13:05:11 2026 GMT
notAfter=Feb 25 13:05:12 2028 GMT
```

---

## Step 8: Test S3 operations

The OCP serving cert is signed by the cluster CA, not a public CA, so clients
outside the cluster need `--no-verify-ssl`. Clients inside the cluster can trust
it by mounting the cluster CA bundle.

```bash
ROUTE=$(oc get route s3-posix -n zgw -o jsonpath='{.spec.host}')

# List buckets
AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy AWS_DEFAULT_REGION=default \
  aws --endpoint-url https://${ROUTE} --no-verify-ssl s3 ls

# Create bucket
AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy AWS_DEFAULT_REGION=default \
  aws --endpoint-url https://${ROUTE} --no-verify-ssl s3 mb s3://tls-test-bucket

# Upload file
echo "hello from raw manifest TLS test" | \
  AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy AWS_DEFAULT_REGION=default \
  aws --endpoint-url https://${ROUTE} --no-verify-ssl s3 cp - s3://tls-test-bucket/hello.txt

# List bucket contents
AWS_ACCESS_KEY_ID=zippy AWS_SECRET_ACCESS_KEY=zippy AWS_DEFAULT_REGION=default \
  aws --endpoint-url https://${ROUTE} --no-verify-ssl s3 ls s3://tls-test-bucket/
# 2026-02-25 14:12:10  33 hello.txt
```

---
