#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

print_header "Phase 4: Cleaning Up Local Files"

print_section "Removing Terraform Working Directory"
print_step "Removing .terraform directory..."
rm -rf "${PROJECT_ROOT}/terraform/.terraform" || print_warning "Failed to remove .terraform"
print_status ".terraform directory removed"

print_section "Removing Environment Files"
if [ -f "${PROJECT_ROOT}/.env.deployment" ]; then
    print_step "Removing .env.deployment..."
    rm -f "${PROJECT_ROOT}/.env.deployment"
    print_status ".env.deployment removed"
fi

print_section "Cleaning Docker Images"
print_step "Removing local Docker image..."
docker rmi -f locust-load-tests:latest 2>/dev/null || print_warning "Docker image not found locally"
print_status "Local Docker images cleaned"

print_section "Removing kubeconfig Context"
print_step "Checking kubeconfig..."
if kubectl config current-context &>/dev/null; then
    current_context=$(kubectl config current-context)
    if [[ "$current_context" == *"locust-cluster"* ]]; then
        print_step "Removing locust-cluster context from kubeconfig..."
        kubectl config delete-context "$current_context" 2>/dev/null || print_warning "Context deletion had issues"
        print_status "Context removed"
    fi
fi

print_section "Local Cleanup Complete"
print_success "All local files cleaned up"
