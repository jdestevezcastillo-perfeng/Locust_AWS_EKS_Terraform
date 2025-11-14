#!/bin/bash

set -euo pipefail

# Disable AWS CLI pager to prevent interactive prompts during automation
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

source "${PROJECT_ROOT}/scripts/common.sh"

ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}

AWS_REGION=""
CLUSTER_NAME=""
CLUSTER_ENDPOINT=""
ECR_REPOSITORY_URL=""

prompt_for_api_cidrs() {
    while true; do
        read -r -p "CIDR(s) allowed to reach the EKS API (comma separated): " input
        local normalized
        normalized="$(echo "$input" | tr -d ' ')"
        if [ -z "$normalized" ]; then
            print_warning "At least one CIDR is required."
            continue
        fi

        if echo "$normalized" | grep -Eq '(^|,)0\.0\.0\.0/0(,|$)' && [ "${ALLOW_INSECURE_ENDPOINT:-false}" != "true" ]; then
            print_warning "0.0.0.0/0 is blocked. Set ALLOW_INSECURE_ENDPOINT=true to override."
            continue
        fi
        CIDR_JSON=$(format_cidrs_to_json "$normalized") || continue
        export TF_VAR_cluster_endpoint_public_access_cidrs="$CIDR_JSON"
        print_success "EKS API restricted to $CIDR_JSON"
        break
    done
}

select_region() {
    local current_region
    current_region=$(aws configure get region 2>/dev/null || echo "")

    declare -A REGIONS=(
        [1]="eu-central-1"
        [2]="us-east-1"
        [3]="us-west-2"
        [4]="eu-west-1"
        [5]="ap-southeast-1"
        [6]="ap-northeast-1"
    )

    print_section "AWS Region"
    print_info "Current AWS CLI region: ${current_region:-not set}"
    for key in "${!REGIONS[@]}"; do
        echo "  $key) ${REGIONS[$key]}"
    done
    echo "  [Enter to keep current]"
    read -p "Region choice: " choice

    if [[ -n "${choice}" && -n "${REGIONS[$choice]:-}" ]]; then
        AWS_REGION="${REGIONS[$choice]}"
    elif [[ -n "$current_region" ]]; then
        AWS_REGION="$current_region"
    else
        error_exit "AWS region is required. Configure via 'aws configure'."
    fi

    export AWS_REGION
    export TF_VAR_aws_region="$AWS_REGION"
    print_success "Using AWS region ${AWS_REGION}"
}

validate_prereqs() {
    print_section "Validating Prerequisites"
    check_commands terraform aws kubectl docker jq || error_exit "Install the missing commands first."
    validate_aws_credentials || error_exit "AWS credentials not configured"
    docker ps >/dev/null || error_exit "Docker daemon not reachable"
    [ -f "${PROJECT_ROOT}/terraform/main.tf" ] || error_exit "terraform/main.tf missing"
    [ -f "${PROJECT_ROOT}/docker/Dockerfile" ] || error_exit "docker/Dockerfile missing"
    print_success "All prerequisites satisfied"
}

run_terraform() {
    print_section "Provisioning AWS Infrastructure"
    pushd "${PROJECT_ROOT}/terraform" >/dev/null

    local plan_args=()
    if [[ -n "${TF_VAR_FILE:-}" ]]; then
        plan_args+=("-var-file=${TF_VAR_FILE}")
    fi

    terraform init -upgrade
    terraform validate
    terraform plan "${plan_args[@]}" -out=tfplan
    terraform apply tfplan
    rm -f tfplan

    CLUSTER_NAME=$(terraform output -raw cluster_name)
    CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || "$AWS_REGION")

    popd >/dev/null

    export CLUSTER_NAME CLUSTER_ENDPOINT ECR_REPOSITORY_URL AWS_REGION

    print_success "Infrastructure ready"
    print_info "Cluster: ${CLUSTER_NAME}"
    print_info "API endpoint: ${CLUSTER_ENDPOINT}"
    print_info "ECR: ${ECR_REPOSITORY_URL}"
}

configure_kubectl() {
    print_section "Configuring kubectl"
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    verify_kubectl_connection || error_exit "kubectl cannot reach the cluster"
    wait_for_condition 300 \
        "[ \$(kubectl get nodes --no-headers | grep -c 'Ready') -gt 0 ]" \
        "EKS nodes to be ready"
    kubectl get nodes
}

build_and_push_image() {
    print_section "Building Docker Image"
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_REPOSITORY_URL"

    docker build \
        --platform linux/amd64 \
        -t "locust-load-tests:${IMAGE_TAG}" \
        -f "${PROJECT_ROOT}/docker/Dockerfile" \
        "${PROJECT_ROOT}"

    docker tag "locust-load-tests:${IMAGE_TAG}" "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
    docker tag "locust-load-tests:${IMAGE_TAG}" "${ECR_REPOSITORY_URL}:latest"

    docker push "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
    docker push "${ECR_REPOSITORY_URL}:latest"
}

deploy_locust() {
    print_section "Deploying Locust Workloads"
    local locust_image="${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
    sed "s|__LOCUST_IMAGE__|${locust_image}|g" \
        "${PROJECT_ROOT}/kubernetes/locust-stack.yaml" | kubectl apply -f -

    wait_for_deployment "locust-master" "locust" 300
    wait_for_deployment "locust-worker" "locust" 300
    wait_for_loadbalancer_ip "locust" "locust-master" 300 || \
        print_warning "LoadBalancer IP still provisioning"

    local lb
    lb=$(get_loadbalancer_ip "locust" "locust-master")
    if [ -n "$lb" ]; then
        print_success "Locust UI: http://${lb}:8089"
    else
        print_warning "LoadBalancer IP not yet assigned. Check with 'kubectl get svc -n locust'."
    fi
}

main() {
    clear
    print_header "LOCUST ON AWS EKS - DEPLOY"

    if ! load_environment_config "$ENVIRONMENT"; then
        error_exit "Unknown environment '${ENVIRONMENT}'. Add config/environments/${ENVIRONMENT}/terraform.tfvars."
    fi

    select_region
    if [ -n "${EKS_API_ALLOWED_CIDRS:-}" ]; then
        local cidr_json
        cidr_json=$(format_cidrs_to_json "$EKS_API_ALLOWED_CIDRS") || \
            error_exit "Unable to parse EKS_API_ALLOWED_CIDRS"
        export TF_VAR_cluster_endpoint_public_access_cidrs="$cidr_json"
        print_success "EKS API restricted to $cidr_json"
    else
        prompt_for_api_cidrs
    fi
    validate_prereqs

    local start_time
    start_time=$(date +%s)

    run_terraform
    configure_kubectl
    build_and_push_image
    deploy_locust

    local duration end_time
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    print_section "Deployment Complete"
    print_success "Total time: $((duration / 60))m $((duration % 60))s"
}

main "$@"
