#!/bin/bash

# Configuration
NAMESPACE=$(oc project -q)
GATEWAY_MANIFEST="examples/openshift/zgw-posix.yaml"
NOTEBOOK_MANIFEST="examples/openshift/zgw-notebook.yaml"
NOTEBOOK_FILE="notebooks/zgw-s3-visual-demo.ipynb"
CONFIGMAP_NAME="zgw-demo-notebook"

usage() {
    echo "Usage: $0 {start|stop}"
    exit 1
}

start_demo() {
    echo " Starting zgw-posix Demo Environment..."

    # 1. Create/Update the Notebook ConfigMap
    echo " Baking notebook into ConfigMap..."
    oc create configmap $CONFIGMAP_NAME --from-file=$NOTEBOOK_FILE --dry-run=client -o yaml | oc apply -f -

    # 2. Deploy the Gateway (S3 Server) if not already present
    if [ -f "$GATEWAY_MANIFEST" ]; then
        echo " Deploying S3 Gateway..."
        oc apply -f $GATEWAY_MANIFEST
    fi

    # 3. Deploy the Notebook Stack (Service, Route, Pod)
    echo " Deploying Jupyter Notebook stack..."
    oc apply -f $NOTEBOOK_MANIFEST

    # 4. Wait for the Pod to be ready
    echo " Waiting for Jupyter Pod to be ready..."
    oc wait --for=condition=ready pod jupyter --timeout=120s

    # 5. Output Access Info
    ROUTE_HOST=$(oc get route jupyter -o jsonpath='{.spec.host}')
    echo "--------------------------------------------------------"
    echo "✅ SUCCESS: Demo environment is LIVE"
    echo " URL: https://$ROUTE_HOST"
    echo "--------------------------------------------------------"
}

stop_demo() {
    echo " Cleaning up demo environment..."
    
    # Remove the Notebook stack
    oc delete -f $NOTEBOOK_MANIFEST --ignore-not-found
    
    # Remove the ConfigMap
    oc delete configmap $CONFIGMAP_NAME --ignore-not-found
    
    # Optional: Wipe the storage (Exec into gateway if it's still running)
    GW_POD=$(oc get pod -l app.kubernetes.io/name=zgw-posix -o name 2>/dev/null)
    if [ ! -z "$GW_POD" ]; then
        echo "🗑️ Wiping S3 data from POSIX backend..."
        oc exec $GW_POD -- rm -rf /var/lib/ceph/rgw_posix_driver/*
        oc exec $GW_POD -- rm -rf /var/lib/ceph/rgw_posix_db/*
    fi

    echo "✅ Demo environment removed."
}

# Logic Switch
case "$1" in
    start)
        start_demo
        ;;
    stop)
        stop_demo
        ;;
    *)
        usage
        ;;
esac
