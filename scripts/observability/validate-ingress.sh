#!/bin/bash
################################################################################
# Ingress Validation Script
#
# Validates all monitoring and Locust services are accessible via the ingress
# LoadBalancer. This script can be run standalone or called by other scripts.
#
# Usage:
#   ./validate-ingress.sh [--namespace <namespace>] [--detailed]
#   ./validate-ingress.sh --help
#
# Options:
#   --namespace <ns>  Validate ingress in specific namespace (default: monitoring)
#   --detailed        Show detailed output including response headers
#   --help            Show this help message
#
# Exit Codes:
#   0 - All services validated successfully
#   1 - One or more services failed validation
#   2 - Ingress LoadBalancer not found or not ready
################################################################################

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/scripts/common.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/common.sh"
else
    # Fallback color definitions if common.sh not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color

    print_error() { echo -e "${RED}✗ $*${NC}" >&2; }
    print_success() { echo -e "${GREEN}✓ $*${NC}"; }
    print_warning() { echo -e "${YELLOW}⚠ $*${NC}"; }
    print_info() { echo -e "${BLUE}ℹ $*${NC}"; }
fi

# Default configuration
NAMESPACE="monitoring"
DETAILED=false
TIMEOUT=10
VALIDATION_FAILURES=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

################################################################################
# Function: get_ingress_url
# Description: Retrieves the ingress LoadBalancer URL
# Returns: Ingress URL or empty string if not found
################################################################################
get_ingress_url() {
    local ingress_name="${1:-monitoring-ingress}"
    local namespace="${2:-monitoring}"

    local ingress_url
    ingress_url=$(kubectl get ingress "${ingress_name}" -n "${namespace}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [[ -z "${ingress_url}" ]]; then
        # Try getting from locust namespace if monitoring fails
        ingress_url=$(kubectl get ingress -n locust locust-ingress \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi

    echo "${ingress_url}"
}

################################################################################
# Function: test_service_endpoint
# Description: Tests a single service endpoint via ingress
# Arguments:
#   $1 - Service name (for display)
#   $2 - Full URL to test
#   $3 - Expected HTTP status codes (comma-separated, e.g., "200,302")
#   $4 - Is optional (true/false, default: false)
# Returns: 0 if successful, 1 if failed
################################################################################
test_service_endpoint() {
    local service_name="$1"
    local url="$2"
    local expected_codes="$3"
    local is_optional="${4:-false}"

    local http_code
    local status_symbol
    local status_color

    # Make HTTP request with timeout
    if ${DETAILED}; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time ${TIMEOUT} --connect-timeout 5 "${url}" 2>&1) || http_code="000"
    else
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time ${TIMEOUT} --connect-timeout 5 "${url}" 2>/dev/null) || http_code="000"
    fi

    # Check if the HTTP code matches any expected codes
    local code_matched=false
    IFS=',' read -ra CODES <<< "${expected_codes}"
    for expected_code in "${CODES[@]}"; do
        if [[ "${http_code}" == "${expected_code}" ]]; then
            code_matched=true
            break
        fi
    done

    # Determine status
    if ${code_matched}; then
        status_symbol="✓"
        status_color="${GREEN}"
        printf "${status_color}${status_symbol} %-20s${NC} %s (HTTP %s)\n" "${service_name}:" "${url}" "${http_code}"
        return 0
    elif [[ "${is_optional}" == "true" ]]; then
        status_symbol="⚠"
        status_color="${YELLOW}"
        printf "${status_color}${status_symbol} %-20s${NC} %s (HTTP %s) - Optional service\n" "${service_name}:" "${url}" "${http_code}"
        return 0
    else
        status_symbol="✗"
        status_color="${RED}"
        printf "${status_color}${status_symbol} %-20s${NC} %s (HTTP %s) - Expected: %s\n" "${service_name}:" "${url}" "${http_code}" "${expected_codes}"
        VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
        return 1
    fi
}

################################################################################
# Main Validation Logic
################################################################################

echo ""
echo "======================================================"
echo "  Ingress Service Validation"
echo "======================================================"
echo ""

# Step 1: Get Ingress LoadBalancer URL
print_info "Retrieving Ingress LoadBalancer URL..."
INGRESS_URL=$(get_ingress_url "monitoring-ingress" "${NAMESPACE}")

if [[ -z "${INGRESS_URL}" ]]; then
    print_error "Ingress LoadBalancer URL not found!"
    print_info "Troubleshooting steps:"
    echo "  1. Check if ingress is deployed: kubectl get ingress -A"
    echo "  2. Check ingress controller: kubectl get svc -n ingress-nginx ingress-nginx-controller"
    echo "  3. View ingress status: kubectl describe ingress -n monitoring monitoring-ingress"
    exit 2
fi

print_success "Ingress LoadBalancer URL: http://${INGRESS_URL}"
echo ""

# Step 2: Test all service endpoints
print_info "Testing service endpoints..."
echo ""

# Monitoring Services
test_service_endpoint "Grafana" "http://${INGRESS_URL}/grafana/" "200,302"
test_service_endpoint "Prometheus" "http://${INGRESS_URL}/prometheus/" "200,302"
test_service_endpoint "VictoriaMetrics" "http://${INGRESS_URL}/victoria/" "200"
test_service_endpoint "AlertManager" "http://${INGRESS_URL}/alertmanager/" "200,302"
test_service_endpoint "Tempo" "http://${INGRESS_URL}/tempo/" "200,302,502" "true"  # Tempo is optional/backend

# Locust Service
test_service_endpoint "Locust" "http://${INGRESS_URL}/locust/" "200"

echo ""
echo "======================================================"

# Step 3: Summary and exit
if [[ ${VALIDATION_FAILURES} -eq 0 ]]; then
    print_success "All services validated successfully! ✓"
    echo ""
    print_info "Access your services at:"
    echo "  • Grafana:        http://${INGRESS_URL}/grafana/"
    echo "  • Prometheus:     http://${INGRESS_URL}/prometheus/"
    echo "  • VictoriaMetrics: http://${INGRESS_URL}/victoria/"
    echo "  • AlertManager:   http://${INGRESS_URL}/alertmanager/"
    echo "  • Locust:         http://${INGRESS_URL}/locust/"
    echo ""
    exit 0
else
    print_error "Validation failed for ${VALIDATION_FAILURES} service(s)!"
    echo ""
    print_info "Troubleshooting steps:"
    echo "  1. Check pod status: kubectl get pods -n monitoring -n locust"
    echo "  2. Check service endpoints: kubectl get svc -n monitoring -n locust"
    echo "  3. View ingress routes: kubectl get ingress -A"
    echo "  4. Check ingress logs: kubectl logs -n ingress-nginx deployment/ingress-nginx-controller"
    echo "  5. Describe failing services: kubectl describe ingress -n monitoring"
    echo ""
    echo "  For detailed troubleshooting, see README.md#troubleshooting"
    echo ""
    exit 1
fi
