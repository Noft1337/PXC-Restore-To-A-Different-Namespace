#!/bin/bash

set -euo pipefail
set +H

# Print nice headers 
print_header() {
    local text="$1"
    local header_char="="
    local header_len=120

    local text_len=${#text}
    local total_text_len=$((text_len + 2))  # including spaces before and after text
    local padding_len=$(( (header_len - total_text_len) / 2 ))
    local extra_char=$(( (header_len - total_text_len) % 2 ))

    local padding
    padding=$(printf "%*s" "$padding_len" "" | tr ' ' "$header_char")
    local line="$padding $text $padding"

    # Add 1 extra character if needed (for odd-length adjustments)
    if [ "$extra_char" -ne 0 ]; then
        line="${line}${header_char}"
    fi

    echo "[*] $line"
}

# Usage: wait_for_resource <resource> <namespace> <label> <timeout>
wait_for_resource() {
    local resource="$1"
    local namespace="$2"
    local labels="$3"
    local timeout="$4"

    until kubectl get "$resource" -n "$namespace" -l "$labels" 2>/dev/null | grep -q '^' > /dev/null; do
        sleep 1
    done
    kubectl wait -n "$namespace" --for=condition=Ready "$resource" -l "$labels" --timeout="${timeout}s"
}

# Initialize cluster
print_header "Creating Cluster"
k3d cluster create "cluster" \
    --servers 1 \
    --agents 3 \
    --k3s-arg '--cluster-cidr=10.50.0.0/16@server:*' \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*" \
    --wait

# Install MetalLB
print_header "Setting up MetalLB"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
# Wait for it to be ready
print_header "Waiting for MetalLB to be Ready"
wait_for_resource "pod" "metallb-system" "component=controller" 120
# Deploy the ip pool 
kubectl create -f network/metallb-ip-pool.yaml
kubectl create -f network/metallb-l2-config.yaml


# Enable NFS
print_header "Installing NFS Support"
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/install-driver.sh | bash -s master --
kubectl create -f storage/nfs-storage-class.yaml
print_header "Waiting for the NFS-CSI to be Ready"
wait_for_resource "pod" "kube-system" "app=csi-nfs-node" 120

# Label Nodes
print_header "Labeling Nodes"
i=0
for node in $(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers -l='!node-role.kubernetes.io/master' | xargs); do
    kubectl label nodes "$node" node-role.kubernetes.io/worker=true
    i=$((i + 1))
    if [[ $i != 2 ]]; then # 2 nodes for prod, 1 for stage
        kubectl label nodes "$node" proxysql=prod
    else
        kubectl label nodes "$node" proxysql=stage
    fi
done

# Set Env Vars
STAGE_REL_NAME="pxc-db-stage"
PROD_REL_NAME="pxc-db-prod"
OPERATOR_REL_NAME="pxc-operator"
# Namespaces
STAGE_NAMESPACE="percona-stage"
PROD_NAMESPACE="percona-prod"
OPERATOR_NAMESPACE="percona-operator"

print_header "Creating Namespaces"
ns_list=("$OPERATOR_NAMESPACE" "$PROD_NAMESPACE" "$STAGE_NAMESPACE")
# Grant access to the relevant namespaces
for ns in "${ns_list[@]}"; do
    kubectl create namespace "$ns"
done

PXC_DB_LABEL='app.kubernetes.io/name=percona-xtradb-cluster'
PXC_OPERATOR_LABEL='app.kubernetes.io/name=pxc-operator'

print_header "Installing Percona Operator"
helm install "$OPERATOR_REL_NAME" -n "$OPERATOR_NAMESPACE" ../pxc-operator/ --values pxc-operator-values.yaml --wait
print_header "Waiting for $OPERATOR_REL_NAME on $OPERATOR_NAMESPACE"
wait_for_resource "pod" "$OPERATOR_NAMESPACE" "$PXC_OPERATOR_LABEL" 120

print_header "Installing $STAGE_REL_NAME on $STAGE_NAMESPACE"
helm install "$STAGE_REL_NAME" -n "$STAGE_NAMESPACE" ../pxc-db --values pxc-db-stage-values.yaml --wait
print_header "Waiting for $STAGE_REL_NAME on $STAGE_NAMESPACE"
wait_for_resource "pod" "$STAGE_NAMESPACE" "$PXC_DB_LABEL" 300

print_header "Installing $PROD_REL_NAME on $PROD_NAMESPACE"
helm install "$PROD_REL_NAME" -n "$PROD_NAMESPACE" ../pxc-db/ --values pxc-db-prod-values.yaml --wait
print_header "Waiting for $PROD_REL_NAME on $PROD_NAMESPACE"
wait_for_resource "pod" "$PROD_NAMESPACE" "$PXC_DB_LABEL" 300

printf "\n\n[*] Finished installing K3D Cluster with Percona"
