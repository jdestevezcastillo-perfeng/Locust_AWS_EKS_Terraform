#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

print_header "Phase 1: Deleting Kubernetes Resources"

print_section "Checking Kubernetes Connectivity"
if ! verify_kubectl_connection 2>/dev/null; then
    print_warning "Not connected to Kubernetes cluster - skipping K8s deletion"
    exit 0
fi

print_section "Deleting Locust Namespace"
print_step "Deleting namespace 'locust' (this will delete all resources in it)..."
kubectl delete namespace locust --ignore-not-found=true || print_warning "Namespace deletion had issues, continuing..."
print_status "Namespace deletion initiated"

print_step "Waiting for namespace deletion (timeout: 2 minutes)..."
wait_for_condition 120 \
    "! kubectl get namespace locust &>/dev/null" \
    "Namespace deletion to complete" || print_warning "Namespace deletion timed out - may still be deleting in background"

print_success "Kubernetes resources deleted"
