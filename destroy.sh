#!/bin/bash

################################################################################
#                                                                              #
#  Locust on AWS EKS - Complete Destruction Script                           #
#  Location: /home/lostborion/Documents/veeam-extended/destroy.sh            #
#                                                                              #
#  This script safely destroys all resources created by deploy.sh:           #
#                                                                              #
#  1. Delete Kubernetes Resources (namespaces, pods, services, etc)          #
#  2. Delete ECR Images (Docker images in registry)                           #
#  3. Destroy AWS Infrastructure (EKS, VPC, RDS, etc via Terraform)          #
#  4. Clean Up Local Files (kubeconfig, Terraform state, etc)                #
#                                                                              #
#  Usage:                                                                      #
#    ./destroy.sh              # Safely destroy all resources                  #
#                                                                              #
#  Total Time: ~15-20 minutes                                                 #
#                                                                              #
#  WARNING: This is a DESTRUCTIVE operation. All data will be lost.          #
#           You will be asked to confirm before proceeding.                   #
#                                                                              #
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source library functions
source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Display warning banner
clear
print_header "⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️"
echo ""
print_error "This script will PERMANENTLY DELETE:"
echo ""
print_status "  • All Kubernetes resources (pods, services, deployments)"
print_status "  • All Docker images in ECR"
print_status "  • All AWS infrastructure (EKS cluster, VPC, nodes)"
print_status "  • All data and logs"
echo ""
print_error "This action CANNOT be undone!"
echo ""

# Confirmation prompt
read -p "Type 'destroy' to confirm: " CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
    print_warning "Destruction cancelled"
    exit 0
fi

echo ""
read -p "Are you absolutely sure? Type 'yes' to proceed: " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "yes" ]; then
    print_warning "Destruction cancelled"
    exit 0
fi

echo ""

# Record start time
START_TIME=$(date +%s)

# Execute destruction phases
print_section "Executing Destruction Phases"
echo ""

print_info "Phase 1/4: Deleting Kubernetes Resources..."
"${PROJECT_ROOT}/scripts/destroy/01-delete-k8s-resources.sh" || print_warning "K8s deletion had issues"
echo ""

print_info "Phase 2/4: Deleting ECR Images..."
"${PROJECT_ROOT}/scripts/destroy/02-delete-ecr-images.sh" || print_warning "ECR deletion had issues"
echo ""

print_info "Phase 3/4: Destroying AWS Infrastructure..."
"${PROJECT_ROOT}/scripts/destroy/03-destroy-infrastructure.sh" || print_warning "Infrastructure destruction had issues"
echo ""

print_info "Phase 4/4: Cleaning Up Local Files..."
"${PROJECT_ROOT}/scripts/destroy/04-cleanup-local.sh" || print_warning "Local cleanup had issues"
echo ""

# Calculate total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Final summary
print_header "DESTRUCTION COMPLETE!"
echo ""
print_warning "All resources have been deleted"
print_info "Total destruction time: ${MINUTES}m ${SECONDS}s"
echo ""

print_section "What Was Deleted"
print_status "  ✓ Kubernetes namespaces and all resources"
print_status "  ✓ ECR images and configurations"
print_status "  ✓ EKS cluster and node groups"
print_status "  ✓ VPC, subnets, and networking"
print_status "  ✓ IAM roles and security groups"
print_status "  ✓ CloudWatch logs"
print_status "  ✓ Local configuration files"
echo ""

print_section "What Remains"
print_status "  • Source code and configuration files in this directory"
print_status "  • Documentation and guides"
print_status "  • Terraform modules and scripts"
echo ""

print_success "You can safely delete this directory or re-deploy with './deploy.sh'"
