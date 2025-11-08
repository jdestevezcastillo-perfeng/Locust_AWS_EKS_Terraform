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
AWS_REGION=${AWS_REGION:-eu-central-1}
IMAGE_TAG=${1:-latest}

print_header "Phase 4: Building and Pushing Docker Image to ECR"

print_section "Authenticating with ECR"
print_step "Getting ECR login credentials..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REPOSITORY_URL" || \
    error_exit "Failed to authenticate with ECR"
print_success "ECR authentication successful"

print_section "Building Docker Image"
print_step "Building image from docker/Dockerfile (tag: $IMAGE_TAG)..."
docker build \
    --platform linux/amd64 \
    --build-arg BUILDKIT_CONTEXT_KEEP_GIT_DIR=1 \
    -t "locust-load-tests:${IMAGE_TAG}" \
    -f "${PROJECT_ROOT}/docker/Dockerfile" \
    "${PROJECT_ROOT}" || error_exit "Docker build failed"
print_success "Docker image built successfully"

print_section "Tagging Image for ECR"
print_step "Tagging as: ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
docker tag "locust-load-tests:${IMAGE_TAG}" "${ECR_REPOSITORY_URL}:${IMAGE_TAG}" || \
    error_exit "Failed to tag image"

print_step "Tagging as: ${ECR_REPOSITORY_URL}:latest"
docker tag "locust-load-tests:${IMAGE_TAG}" "${ECR_REPOSITORY_URL}:latest" || \
    error_exit "Failed to tag image as latest"
print_success "Image tagged for ECR"

print_section "Pushing Image to ECR"
print_step "Pushing ${ECR_REPOSITORY_URL}:${IMAGE_TAG}..."
docker push "${ECR_REPOSITORY_URL}:${IMAGE_TAG}" || error_exit "Failed to push image"
print_success "Image pushed to ECR"

print_step "Pushing ${ECR_REPOSITORY_URL}:latest..."
docker push "${ECR_REPOSITORY_URL}:latest" || error_exit "Failed to push latest tag"
print_success "Latest tag pushed to ECR"

print_section "Image Build and Push Complete"
print_info "Image URL: ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
print_success "Docker image successfully built and pushed to ECR"
