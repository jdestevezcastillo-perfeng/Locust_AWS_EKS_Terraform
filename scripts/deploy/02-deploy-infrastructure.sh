#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

print_header "Phase 2: Deploying AWS Infrastructure with Terraform"

cd "${PROJECT_ROOT}/terraform"

print_section "Initializing Terraform"
print_step "Running terraform init..."
terraform init -upgrade || error_exit "Terraform initialization failed"
print_success "Terraform initialized"

print_section "Validating Terraform Configuration"
print_step "Running terraform validate..."
terraform validate || error_exit "Terraform validation failed"
print_success "Terraform configuration is valid"

print_section "Planning Terraform Deployment"
print_step "Running terraform plan..."
terraform plan -out=tfplan || error_exit "Terraform plan failed"
print_success "Terraform plan created"

print_section "Applying Terraform Configuration"
print_step "This will create AWS resources (takes 15-20 minutes)..."
terraform apply tfplan || error_exit "Terraform apply failed"
print_success "AWS infrastructure deployed successfully"

# Clean up plan file
rm -f tfplan

print_section "Capturing Infrastructure Outputs"
export CLUSTER_NAME=$(get_tf_output "cluster_name")
export CLUSTER_ENDPOINT=$(get_tf_output "cluster_endpoint")
export ECR_REPOSITORY_URL=$(get_tf_output "ecr_repository_url")
export AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")

print_info "Cluster Name: $CLUSTER_NAME"
print_info "Cluster Endpoint: $CLUSTER_ENDPOINT"
print_info "ECR Repository: $ECR_REPOSITORY_URL"
print_info "AWS Region: $AWS_REGION"

# Save outputs for other scripts
cat > "${PROJECT_ROOT}/.env.deployment" <<EOF
export CLUSTER_NAME="${CLUSTER_NAME}"
export CLUSTER_ENDPOINT="${CLUSTER_ENDPOINT}"
export ECR_REPOSITORY_URL="${ECR_REPOSITORY_URL}"
export AWS_REGION="${AWS_REGION}"
EOF

print_success "Infrastructure deployed and outputs captured"
