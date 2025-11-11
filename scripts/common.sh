#!/bin/bash

set -euo pipefail

# Resolve project root relative to this helper
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${COMMON_DIR}/.." && pwd)"

# ------------------------------------------------------------------------------
# Color helpers
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▶ $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_step() {
    echo -e "${MAGENTA}→ $1${NC}"
}

print_status() {
    echo -e "${CYAN}  ⊙ $1${NC}"
}

error_exit() {
    print_error "$1"
    exit 1
}

trap 'error_exit "Script failed at line $LINENO"' ERR

# ------------------------------------------------------------------------------
# Validation helpers
# ------------------------------------------------------------------------------
check_command() {
    local cmd=$1
    command -v "$cmd" &>/dev/null
}

check_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        return 1
    fi
    return 0
}

validate_aws_credentials() {
    if ! aws sts get-caller-identity &>/dev/null; then
        return 1
    fi
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    print_success "AWS credentials valid (Account: ${account_id})"
    return 0
}

get_aws_account_id() {
    aws sts get-caller-identity --query Account --output text
}

get_aws_region() {
    aws configure get region 2>/dev/null || echo "us-east-1"
}

verify_kubectl_connection() {
    if ! kubectl cluster-info &>/dev/null; then
        return 1
    fi
    print_success "kubectl can reach the cluster"
    return 0
}

# ------------------------------------------------------------------------------
# Terraform helpers
# ------------------------------------------------------------------------------
get_tf_output() {
    local output_name=$1
    (cd "${PROJECT_ROOT}/terraform" && terraform output -raw "${output_name}") 2>/dev/null || echo ""
}

format_cidrs_to_json() {
    local input="$1"
    local entries=""
    IFS=',' read -ra cidrs <<<"$input"
    for cidr in "${cidrs[@]}"; do
        local trimmed
        trimmed="$(echo "$cidr" | awk '{$1=$1};1')"
        [ -z "$trimmed" ] && continue
        entries+="${entries:+, }\"$trimmed\""
    done

    if [ -z "$entries" ]; then
        echo ""
        return 1
    fi

    printf '[%s]\n' "$entries"
}

load_environment_config() {
    local environment=${1:-dev}
    local config_file="${PROJECT_ROOT}/config/environments/${environment}/terraform.tfvars"
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    export DEPLOY_ENVIRONMENT="$environment"
    export TF_VAR_FILE="$config_file"
    return 0
}

# ------------------------------------------------------------------------------
# Kubernetes helpers
# ------------------------------------------------------------------------------
wait_for_condition() {
    local timeout=${1:-300}
    local condition=$2
    local description=$3
    local start_time
    start_time=$(date +%s)

    print_status "Waiting for ${description} (timeout ${timeout}s)"
    while ! eval "$condition" &>/dev/null; do
        if [ $(( $(date +%s) - start_time )) -gt "$timeout" ]; then
            print_error "Timeout waiting for ${description}"
            return 1
        fi
        sleep 5
    done
    print_success "${description}"
    return 0
}

wait_for_deployment() {
    local deployment=$1
    local namespace=${2:-locust}
    local timeout=${3:-300}
    wait_for_condition "$timeout" \
        "kubectl get deployment $deployment -n $namespace -o jsonpath='{.status.readyReplicas}' | grep -q '[1-9]'" \
        "Deployment $deployment ready"
}

get_loadbalancer_ip() {
    local namespace=${1:-locust}
    local service=${2:-locust-master}
    kubectl get svc "$service" -n "$namespace" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    kubectl get svc "$service" -n "$namespace" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
    echo ""
}

wait_for_loadbalancer_ip() {
    local namespace=${1:-locust}
    local service=${2:-locust-master}
    local timeout=${3:-300}
    wait_for_condition "$timeout" \
        "[[ -n \"\$(get_loadbalancer_ip $namespace $service)\" ]]" \
        "LoadBalancer IP for $service"
}

wait_for_k8s_resource() {
    local type=$1
    local name=$2
    local namespace=${3:-locust}
    local timeout=${4:-300}
    wait_for_condition "$timeout" \
        "kubectl get $type $name -n $namespace &>/dev/null" \
        "$type/$name available"
}

get_pod_count() {
    local label=$1
    local namespace=${2:-locust}
    kubectl get pods -n "$namespace" -l "$label" --no-headers 2>/dev/null | wc -l
}

export PROJECT_ROOT
