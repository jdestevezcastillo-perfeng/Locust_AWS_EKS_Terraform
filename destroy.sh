#!/bin/bash

set -euo pipefail

# Disable AWS CLI pager to prevent interactive prompts during automation
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

source "${PROJECT_ROOT}/scripts/common.sh"

wait_for_eni_cleanup() {
    print_section "Waiting for Network Interfaces Cleanup"

    local vpc_id region max_wait=300 elapsed=0
    vpc_id=$(get_tf_output "vpc_id" 2>/dev/null)
    region=$(get_tf_output "aws_region" 2>/dev/null)
    region=${region:-$(get_aws_region)}

    if [ -z "$vpc_id" ]; then
        print_warning "VPC ID not found in Terraform outputs - skipping ENI check"
        return 0
    fi

    print_info "Checking for remaining ENIs in VPC ${vpc_id}..."

    while [ $elapsed -lt $max_wait ]; do
        local eni_count
        eni_count=$(aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=${vpc_id}" "Name=status,Values=in-use" \
            --region "${region}" \
            --query 'length(NetworkInterfaces)' \
            --output text 2>/dev/null || echo "0")

        if [ "$eni_count" = "0" ] || [ -z "$eni_count" ]; then
            print_success "All ENIs released from VPC"
            return 0
        fi

        print_info "Waiting for ${eni_count} ENI(s) to be released... (${elapsed}s/${max_wait}s)"
        sleep 10
        elapsed=$((elapsed + 10))
    done

    print_warning "Timeout waiting for ENIs - Terraform destroy may fail"
    print_info "Run: aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${vpc_id} --region ${region}"
}

delete_k8s_resources() {
    print_section "Deleting Kubernetes Resources"
    if ! verify_kubectl_connection; then
        print_warning "kubectl not configured, skipping Kubernetes cleanup"
        return
    fi

    # Step 1: Delete LoadBalancer services explicitly to trigger ENI cleanup
    print_info "Deleting LoadBalancer services..."

    # Delete nginx Ingress LoadBalancer (blocks subnet deletion)
    if kubectl get svc ingress-nginx-controller -n ingress-nginx &>/dev/null; then
        print_info "Deleting nginx Ingress LoadBalancer..."
        kubectl delete svc ingress-nginx-controller -n ingress-nginx --timeout=5m || \
            print_warning "Failed to delete ingress-nginx LoadBalancer"
    fi

    # Delete any Locust LoadBalancers (shouldn't exist with ClusterIP, but just in case)
    if kubectl get svc locust-master -n locust &>/dev/null; then
        local svc_type
        svc_type=$(kubectl get svc locust-master -n locust -o jsonpath='{.spec.type}')
        if [ "$svc_type" = "LoadBalancer" ]; then
            print_info "Deleting Locust LoadBalancer..."
            kubectl delete svc locust-master -n locust --timeout=5m || \
                print_warning "Failed to delete locust LoadBalancer"
        fi
    fi

    # Step 2: Delete namespaces with proper waiting
    print_info "Deleting namespaces..."

    # Delete ingress-nginx namespace (critical - was missing in original!)
    kubectl delete namespace ingress-nginx --ignore-not-found --wait=true --timeout=10m || \
        print_warning "ingress-nginx namespace deletion reported issues"

    # Delete locust namespace
    kubectl delete namespace locust --ignore-not-found --wait=true --timeout=10m || \
        print_warning "locust namespace deletion reported issues"

    # Step 3: Wait for ENIs to be released before Terraform destroy
    wait_for_eni_cleanup
}

delete_ecr_images() {
    print_section "Removing ECR Images"
    local repo_url repo_name region
    repo_url=$(get_tf_output "ecr_repository_url")
    region=$(get_tf_output "aws_region")

    if [ -z "$repo_url" ]; then
        print_warning "ECR repository output not found – skipping image deletion"
        return
    fi

    repo_name="${repo_url##*/}"
    region=${region:-$(get_aws_region)}

    if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$region" &>/dev/null; then
        print_warning "Repository ${repo_name} missing – skipping"
        return
    fi

    local image_ids
    image_ids=$(aws ecr list-images --repository-name "$repo_name" --region "$region" --query 'imageIds' --output json)
    if [[ "$image_ids" == "[]" ]]; then
        print_info "No images to delete in ${repo_name}"
        return
    fi

    aws ecr batch-delete-image \
        --repository-name "$repo_name" \
        --image-ids "$image_ids" \
        --region "$region" || print_warning "Some images may remain in ${repo_name}"
}

destroy_infrastructure() {
    print_section "Destroying Terraform Infrastructure"
    pushd "${PROJECT_ROOT}/terraform" >/dev/null

    if [ ! -f "terraform.tfstate" ]; then
        print_warning "terraform.tfstate missing – resources may already be gone"
        popd >/dev/null
        return
    fi

    terraform plan -destroy -out=tfplan
    terraform apply tfplan
    rm -f tfplan terraform.tfstate terraform.tfstate.backup
    popd >/dev/null
}

cleanup_local() {
    print_section "Cleaning Local Artifacts"
    rm -rf "${PROJECT_ROOT}/terraform/.terraform"
    docker rmi -f locust-load-tests:latest 2>/dev/null || true

    local current_context
    if current_context=$(kubectl config current-context 2>/dev/null) && [[ "$current_context" == *"locust"* ]]; then
        kubectl config delete-context "$current_context" || true
    fi
}

confirm_destruction() {
    clear
    print_header "⚠ LOCUST DEPLOYMENT CLEANUP ⚠"
    print_error "All Kubernetes resources, AWS infrastructure, and Docker images will be deleted."
    read -p "Type 'destroy' to continue: " confirm
    [[ "$confirm" == "destroy" ]] || { print_warning "Cancelled"; exit 0; }
    read -p "Type 'yes' to confirm again: " final_confirm
    [[ "$final_confirm" == "yes" ]] || { print_warning "Cancelled"; exit 0; }
}

main() {
    confirm_destruction
    local start_time
    start_time=$(date +%s)

    delete_k8s_resources
    delete_ecr_images
    destroy_infrastructure
    cleanup_local

    local end_time=$(( $(date +%s) - start_time ))
    print_section "Cleanup Complete"
    print_success "Total time: $((end_time / 60))m $((end_time % 60))s"
}

main "$@"
