#!/bin/bash

################################################################################
#                                                                              #
#  Locust on AWS EKS - Complete Deployment Script                            #
#  Location: /home/lostborion/Documents/veeam-extended/deploy.sh             #
#                                                                              #
#  This script orchestrates the complete deployment of a distributed Locust  #
#  load testing environment on AWS EKS with the following phases:            #
#                                                                              #
#  1. Validate Prerequisites (terraform, aws-cli, kubectl, docker, jq)        #
#  2. Deploy AWS Infrastructure (VPC, EKS, ECR, CloudWatch via Terraform)    #
#  3. Configure kubectl (update kubeconfig, verify cluster access)            #
#  4. Build & Push Docker Image (to ECR)                                      #
#  5. Deploy to Kubernetes (master, workers, HPA, services)                   #
#                                                                              #
#  Usage:                                                                      #
#    ./deploy.sh               # Deploy with default environment (dev)        #
#    ./deploy.sh dev           # Deploy to dev environment                    #
#    ./deploy.sh staging       # Deploy to staging environment                #
#    ./deploy.sh prod v1.2.3   # Deploy prod with specific image tag          #
#                                                                              #
#  Total Time: ~30-40 minutes                                                 #
#  (Infrastructure: 15-20min, Build & Push: 3-5min, K8s: 2-3min)             #
#                                                                              #
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source library functions
source "${PROJECT_ROOT}/scripts/lib/colors.sh"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Parse arguments
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}

# Display banner
clear
print_header "LOCUST ON AWS EKS - COMPLETE DEPLOYMENT"
echo ""

# Interactive AWS Region Selection
print_section "AWS Configuration"
echo ""

# Get current AWS region setting
CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "not set")
print_info "Current AWS region: $CURRENT_REGION"
echo ""

# Common AWS regions
declare -A REGIONS=(
    [1]="eu-central-1   (Frankfurt - default)"
    [2]="us-east-1      (Virginia)"
    [3]="us-west-2      (Oregon)"
    [4]="eu-west-1      (Ireland)"
    [5]="ap-southeast-1 (Singapore)"
    [6]="ap-northeast-1 (Tokyo)"
)

print_step "Select AWS region for deployment:"
echo ""
for key in "${!REGIONS[@]}"; do
    echo "  $key) ${REGIONS[$key]}"
done
echo "  [Press Enter for current region ($CURRENT_REGION)]"
echo ""

read -p "Enter region number (1-6) or press Enter: " REGION_CHOICE

case $REGION_CHOICE in
    1) AWS_REGION="eu-central-1" ;;
    2) AWS_REGION="us-east-1" ;;
    3) AWS_REGION="us-west-2" ;;
    4) AWS_REGION="eu-west-1" ;;
    5) AWS_REGION="ap-southeast-1" ;;
    6) AWS_REGION="ap-northeast-1" ;;
    *) AWS_REGION="$CURRENT_REGION" ;;
esac

if [ "$AWS_REGION" = "not set" ]; then
    print_warning "⚠️  AWS region not set!"
    print_info "Please configure AWS region using: aws configure"
    exit 1
fi

print_success "Using region: $AWS_REGION"
echo ""

# Export region for Terraform
export AWS_REGION
export TF_VAR_aws_region="$AWS_REGION"

print_info "Environment: $ENVIRONMENT"
print_info "Image Tag: $IMAGE_TAG"
print_info "Project Root: $PROJECT_ROOT"
echo ""

# Record start time
START_TIME=$(date +%s)

# Execute deployment phases
print_section "Executing Deployment Phases"
echo ""

print_info "Phase 1/5: Validating Prerequisites..."
"${PROJECT_ROOT}/scripts/deploy/01-validate-prereqs.sh" || {
    print_error "Prerequisites validation failed"
    exit 1
}
echo ""

print_info "Phase 2/5: Deploying AWS Infrastructure..."
"${PROJECT_ROOT}/scripts/deploy/02-deploy-infrastructure.sh" || {
    print_error "Infrastructure deployment failed"
    exit 1
}
echo ""

print_info "Phase 3/5: Configuring kubectl..."
"${PROJECT_ROOT}/scripts/deploy/03-configure-kubectl.sh" || {
    print_error "kubectl configuration failed"
    exit 1
}
echo ""

print_info "Phase 4/5: Building and Pushing Docker Image..."
"${PROJECT_ROOT}/scripts/deploy/04-build-push-image.sh" "$IMAGE_TAG" || {
    print_error "Docker build/push failed"
    exit 1
}
echo ""

print_info "Phase 5/5: Deploying to Kubernetes..."
"${PROJECT_ROOT}/scripts/deploy/05-deploy-kubernetes.sh" || {
    print_error "Kubernetes deployment failed"
    exit 1
}
echo ""

# Calculate total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Final summary
print_header "DEPLOYMENT COMPLETE!"
echo ""
print_section "Summary"
print_success "All deployment phases completed successfully"
print_info "Total deployment time: ${MINUTES}m ${SECONDS}s"
echo ""

# Get LoadBalancer URL
if [ -f "${PROJECT_ROOT}/.env.deployment" ]; then
    source "${PROJECT_ROOT}/.env.deployment"
fi

LOADBALANCER_IP=$(kubectl get svc locust-master -n locust -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                  kubectl get svc locust-master -n locust -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
                  echo "pending")

if [ "$LOADBALANCER_IP" != "pending" ] && [ ! -z "$LOADBALANCER_IP" ]; then
    print_section "Access Your Locust Cluster"
    print_success "Locust Web UI available at:"
    echo ""
    print_status "http://${LOADBALANCER_IP}:8089"
    echo ""
else
    print_section "Locust Web UI"
    print_warning "LoadBalancer IP not yet assigned (may take 1-2 more minutes)"
    print_info "Check status with:"
    print_status "  kubectl get svc locust-master -n locust"
    echo ""
    print_info "Or port-forward locally:"
    print_status "  kubectl port-forward -n locust svc/locust-master 8089:8089"
    echo ""
fi

print_section "Next Steps"
print_step "1. Wait for LoadBalancer IP assignment (check in 2-3 minutes)"
print_step "2. Access Locust web UI at the URL above"
print_step "3. Configure load test parameters"
print_step "4. Start load test"
print_step "5. Monitor metrics and results"
echo ""

print_section "Useful Commands"
echo ""
print_status "View pods:"
print_info "  kubectl get pods -n locust"
echo ""
print_status "View logs (master):"
print_info "  kubectl logs deployment/locust-master -n locust"
echo ""
print_status "View logs (workers):"
print_info "  kubectl logs deployment/locust-worker -n locust"
echo ""
print_status "Monitor autoscaling:"
print_info "  kubectl get hpa -n locust -w"
echo ""
print_status "Scale workers manually:"
print_info "  kubectl scale deployment locust-worker --replicas=10 -n locust"
echo ""
print_status "Port-forward for local access:"
print_info "  kubectl port-forward -n locust svc/locust-master 8089:8089"
echo ""

print_section "Cleanup"
print_warning "To destroy all resources when done, run:"
echo ""
print_status "  ./destroy.sh"
echo ""

print_success "Deployment script completed successfully!"
