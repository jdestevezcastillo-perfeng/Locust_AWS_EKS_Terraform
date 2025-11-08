#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

print_header "Phase 3: Destroying AWS Infrastructure with Terraform"

cd "${PROJECT_ROOT}/terraform"

print_section "Checking Terraform State"
if [ ! -f "terraform.tfstate" ]; then
    print_warning "No Terraform state file found - infrastructure may already be destroyed"
    exit 0
fi
print_success "Terraform state file found"

print_section "Planning Infrastructure Destruction"
print_step "Running terraform plan for destruction..."
terraform plan -destroy -out=tfplan || error_exit "Terraform plan failed"
print_success "Destruction plan created"

print_section "Destroying Infrastructure"
print_step "This will destroy all AWS resources (takes 10-15 minutes)..."
terraform apply tfplan || error_exit "Terraform destroy failed"
print_success "Infrastructure destroyed successfully"

# Clean up plan file
rm -f tfplan

# Clean up state files
rm -f terraform.tfstate terraform.tfstate.backup

print_success "Terraform cleanup complete"
