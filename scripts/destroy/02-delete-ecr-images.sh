#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Load deployment environment for repository metadata
if [ -f "${PROJECT_ROOT}/.env.deployment" ]; then
    source "${PROJECT_ROOT}/.env.deployment"
fi

AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "eu-central-1")}
ECR_REPOSITORY=${ECR_REPOSITORY_URL##*/}  # fall back to repo name from URL
if [ -z "$ECR_REPOSITORY" ]; then
    ECR_REPOSITORY="locust-load-tests"
fi

print_header "Phase 2: Deleting ECR Images"

print_section "Checking ECR Repository"
if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" &>/dev/null; then
    print_warning "ECR repository not found - skipping image deletion"
    exit 0
fi
print_success "ECR repository found"

print_section "Listing Images in Repository"
image_count=$(aws ecr list-images --repository-name "$ECR_REPOSITORY" --region "$AWS_REGION" --query 'imageIds | length(@)' --output text)
print_info "Found $image_count images in repository"

if [ "$image_count" -eq 0 ]; then
    print_info "No images to delete"
else
    print_section "Deleting All Images"
    print_step "Deleting images from $ECR_REPOSITORY..."

    # Get all image IDs
    image_ids=$(aws ecr list-images --repository-name "$ECR_REPOSITORY" --region "$AWS_REGION" --query 'imageIds' --output json)

    if [ ! -z "$image_ids" ] && [ "$image_ids" != "[]" ]; then
        aws ecr batch-delete-image \
            --repository-name "$ECR_REPOSITORY" \
            --image-ids "$image_ids" \
            --region "$AWS_REGION" || print_warning "Some images may not have been deleted"
        print_success "Images deleted from ECR"
    fi
fi

print_success "ECR image deletion complete"
