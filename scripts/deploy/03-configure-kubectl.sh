#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Load deployment environment
if [ -f "${PROJECT_ROOT}/.env.deployment" ]; then
    source "${PROJECT_ROOT}/.env.deployment"
fi

CLUSTER_NAME=${CLUSTER_NAME:-$(get_tf_output "cluster_name")}
AWS_REGION=${AWS_REGION:-eu-central-1}

print_header "Phase 3: Configuring kubectl for EKS Cluster"

print_section "Updating kubeconfig"
print_step "Configuring kubectl to connect to cluster: $CLUSTER_NAME"
aws eks update-kubeconfig \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" || error_exit "Failed to update kubeconfig"
print_success "kubeconfig updated"

print_section "Verifying Cluster Connection"
print_step "Testing kubectl connection..."
verify_kubectl_connection || error_exit "Failed to connect to cluster"

print_step "Getting cluster info..."
kubectl cluster-info || error_exit "Failed to get cluster info"

print_section "Checking Node Status"
print_step "Waiting for nodes to be ready..."
wait_for_condition 300 \
    "[ \$(kubectl get nodes --no-headers 2>/dev/null | grep -c 'Ready') -gt 0 ]" \
    "Node(s) to be ready" || error_exit "Nodes did not become ready in time"

print_step "Node status:"
kubectl get nodes
print_success "Nodes are ready"

print_section "Cluster Configuration Complete"
print_success "kubectl is configured and cluster is healthy"
