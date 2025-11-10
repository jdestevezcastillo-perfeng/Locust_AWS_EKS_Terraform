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

ECR_REPOSITORY_URL=${ECR_REPOSITORY_URL:-$(get_tf_output "ecr_repository_url")}
IMAGE_TAG=${IMAGE_TAG:-latest}
LOCUST_IMAGE="${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

TMP_MANIFEST_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_MANIFEST_DIR"' EXIT

print_header "Phase 5: Deploying Locust to Kubernetes"

print_section "Preparing Kubernetes Manifests"
print_step "Rendering manifests with image ${LOCUST_IMAGE}..."
for manifest in "${PROJECT_ROOT}/kubernetes/base"/*.yaml; do
    manifest_name=$(basename "$manifest")
    sed "s|__LOCUST_IMAGE__|${LOCUST_IMAGE}|g" "$manifest" > "${TMP_MANIFEST_DIR}/${manifest_name}"
done
print_success "Manifests updated"

APPLY_DIR="$TMP_MANIFEST_DIR"

print_section "Creating Kubernetes Namespace"
print_step "Applying namespace.yaml..."
kubectl apply -f "${APPLY_DIR}/namespace.yaml" || error_exit "Failed to create namespace"
print_success "Namespace created"

print_section "Creating ConfigMap"
print_step "Applying configmap.yaml..."
kubectl apply -f "${APPLY_DIR}/configmap.yaml" || error_exit "Failed to create configmap"
print_success "ConfigMap created"

print_section "Deploying Locust Master"
print_step "Applying master-deployment.yaml..."
kubectl apply -f "${APPLY_DIR}/master-deployment.yaml" || error_exit "Failed to deploy master"
print_success "Master deployment created"

print_step "Waiting for master pod to be ready (timeout: 5 minutes)..."
wait_for_deployment "locust-master" "locust" 300 || error_exit "Master pod failed to become ready"
print_success "Master pod is ready"

print_section "Creating Locust Master Service"
print_step "Applying master-service.yaml..."
kubectl apply -f "${APPLY_DIR}/master-service.yaml" || error_exit "Failed to create service"
print_success "Master service created"

print_step "Applying master-internal-service.yaml..."
kubectl apply -f "${APPLY_DIR}/master-internal-service.yaml" || error_exit "Failed to create internal service"
print_success "Internal master service created"

print_section "Deploying Locust Workers"
print_step "Applying worker-deployment.yaml..."
kubectl apply -f "${APPLY_DIR}/worker-deployment.yaml" || error_exit "Failed to deploy workers"
print_success "Worker deployment created"

print_step "Waiting for worker pods to be ready (timeout: 5 minutes)..."
wait_for_deployment "locust-worker" "locust" 300 || error_exit "Worker pods failed to become ready"
print_success "Worker pods are ready"

print_section "Configuring Auto-scaling"
print_step "Applying HPA configuration..."
kubectl apply -f "${APPLY_DIR}/worker-hpa.yaml" || error_exit "Failed to apply HPA"
print_success "Horizontal Pod Autoscaler configured"

print_section "Waiting for LoadBalancer IP"
print_step "This may take 1-2 minutes..."
wait_for_loadbalancer_ip "locust" "locust-master" 300 || print_warning "LoadBalancer IP not yet assigned"

LOADBALANCER_IP=$(get_loadbalancer_ip "locust" "locust-master")
if [ ! -z "$LOADBALANCER_IP" ]; then
    print_info "LoadBalancer IP: $LOADBALANCER_IP"
    print_info "Access Locust UI at: http://${LOADBALANCER_IP}:8089"
else
    print_warning "LoadBalancer IP not yet assigned - may take a few more minutes"
    print_info "Check status with: kubectl get svc locust-master -n locust"
fi

print_section "Kubernetes Deployment Complete"
print_success "Locust cluster successfully deployed to Kubernetes"
