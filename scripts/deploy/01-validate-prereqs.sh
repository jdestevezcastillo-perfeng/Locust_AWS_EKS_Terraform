#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

print_header "Phase 1: Validating Prerequisites"

print_section "Checking Required Commands"
required_commands=(terraform aws kubectl docker jq)
check_commands "${required_commands[@]}" || error_exit "Please install missing commands"
print_success "All required commands found"

print_section "Validating AWS Credentials"
validate_aws_credentials || error_exit "AWS credentials invalid"

print_section "Checking AWS Permissions"
print_step "Verifying IAM permissions..."
aws iam get-user &>/dev/null || error_exit "No IAM permissions - check AWS credentials"
print_success "IAM permissions verified"

print_section "Checking Docker Installation"
print_step "Verifying Docker daemon..."
docker ps &>/dev/null || error_exit "Docker daemon not running"
print_success "Docker daemon running"

print_section "Validating Configuration Files"
if [ ! -d "${PROJECT_ROOT}/terraform" ]; then
    error_exit "Terraform directory not found"
fi
print_success "Terraform directory exists"

if [ ! -f "${PROJECT_ROOT}/terraform/main.tf" ]; then
    error_exit "terraform/main.tf not found"
fi
print_success "Terraform configuration found"

if [ ! -f "${PROJECT_ROOT}/docker/Dockerfile" ]; then
    error_exit "docker/Dockerfile not found"
fi
print_success "Dockerfile found"

if [ ! -f "${PROJECT_ROOT}/pyproject.toml" ]; then
    error_exit "pyproject.toml not found"
fi
print_success "Python dependencies configuration found"

print_section "Prerequisites Validation Complete"
print_success "All prerequisites met - ready for deployment"
