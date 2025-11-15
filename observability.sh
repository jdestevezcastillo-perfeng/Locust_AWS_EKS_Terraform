#!/bin/bash

################################################################################
#                                                                              #
#  Observability Control Script                                              #
#  Location: ./observability.sh                                              #
#                                                                              #
#  This is a convenience wrapper for observability operations.                #
#  Provides easy access to setup, cleanup, and status commands.              #
#                                                                              #
#  Usage:                                                                      #
#    ./observability.sh setup              # Deploy Prometheus & Grafana     #
#    ./observability.sh url                # Get ingress LoadBalancer URL    #
#    ./observability.sh cleanup            # Remove observability stack      #
#    ./observability.sh status             # Check observability status      #
#    ./observability.sh logs               # View pod logs                    #
#    ./observability.sh validate           # Validate ingress endpoints      #
#    ./observability.sh port-forward       # Port-forward (troubleshooting)  #
#    ./observability.sh help               # Show this help message          #
#                                                                              #
#  Primary Access: All services accessible via single ingress LoadBalancer.   #
#  Run './observability.sh url' to get access URLs after setup.              #
#                                                                              #
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source library functions
source "${PROJECT_ROOT}/scripts/common.sh"

# Configuration
NAMESPACE_MONITORING="monitoring"
OBSERVABILITY_DIR="${PROJECT_ROOT}/scripts/observability"
ACCESS_REPORT_FILE="${PROJECT_ROOT}/reports/observability-access.md"
PROM_HELM_RELEASE="prometheus-grafana"
VICTORIA_HELM_RELEASE="victoria-metrics"
LOKI_HELM_RELEASE="loki"
TEMPO_HELM_RELEASE="tempo"
PROM_SERVICE_NAME="${PROM_HELM_RELEASE}-kube-prometheus-prometheus"

# Load observability environment if available
load_observability_env() {
    local env_file="${PROJECT_ROOT}/.env.observability"
    if [ -f "$env_file" ]; then
        # shellcheck disable=SC1090
        source "$env_file"
    fi
}

# Persist helpful URLs/commands for quick reference after setup
generate_access_report() {
    load_observability_env

    local grafana_password="${GRAFANA_ADMIN_PASSWORD:-admin123}"

    # Get Ingress LoadBalancer URL
    local ingress_lb
    ingress_lb=$(get_loadbalancer_ip "ingress-nginx" "ingress-nginx-controller" || true)

    local base_url ingress_status
    if [ -n "$ingress_lb" ]; then
        base_url="http://${ingress_lb}"
        ingress_status="✅ Active"
    else
        base_url="(pending)"
        ingress_status="⏳ LoadBalancer provisioning... Check with \`kubectl get svc -n ingress-nginx ingress-nginx-controller\`"
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    mkdir -p "${PROJECT_ROOT}/reports"

    cat > "$ACCESS_REPORT_FILE" <<EOF
# Observability Access Links

_Last updated: ${timestamp}_

## Ingress LoadBalancer

**Status:** ${ingress_status}

All services are accessible via a single nginx Ingress LoadBalancer (saves ~\$72/month vs separate LoadBalancers).

## Service Endpoints

| Service | URL | Notes |
| --- | --- | --- |
| **Grafana** | ${base_url}/grafana | Dashboard UI. Credentials: \`admin\` / \`${grafana_password}\` |
| **Prometheus** | ${base_url}/prometheus | Metrics query UI and targets: \`/prometheus/targets\` |
| **VictoriaMetrics** | ${base_url}/victoria | Long-term metrics storage. Query path: \`/victoria/select/\` |
| **AlertManager** | ${base_url}/alertmanager | Alert management UI |
| **Tempo** | ${base_url}/tempo | Distributed tracing UI (Jaeger UI) |
| **Locust** | ${base_url}/locust | Load testing web UI. Metrics: \`/locust/metrics\` |

## Internal Services

These services are only accessible from within the cluster:

| Service | Type | Access Method |
| --- | --- | --- |
| **Loki** | ClusterIP | Query via Grafana datasource \`Loki\` or port-forward: \`kubectl port-forward -n monitoring svc/${LOKI_HELM_RELEASE:-loki}-loki 3100:3100\` |

## Quick Commands

\`\`\`bash
# Get LoadBalancer URL
./observability.sh url

# Check Ingress status
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Validate ingress endpoints (HTTP status + UI content)
./observability.sh validate --detailed

# View all Ingress rules
kubectl get ingress -A
\`\`\`

---
💰 **Cost Savings:** Using 1 nginx Ingress LoadBalancer instead of 6 separate LoadBalancers saves approximately \$90/month on AWS.
EOF

    print_success "Access instructions saved to ${ACCESS_REPORT_FILE#$PROJECT_ROOT/}"
}

# Function to show help
show_help() {
    cat << EOF
$(print_header "Observability Control Script")

Usage: ./observability.sh <command> [options]

Commands:

  setup               Deploy Prometheus and Grafana observability stack
                      Options:
                        --skip-helm    Skip helm repository setup

  cleanup             Remove observability stack
                      Options:
                        --force        Force cleanup without prompts

  status              Check status of observability components

  logs                View logs from observability pods
                      Options:
                        --component    Specify component (prometheus, grafana, etc.)
                        --follow       Follow logs in real-time

  url                 Get Ingress LoadBalancer URL and service endpoints
                      Aliases: urls, access
                      Shows all available monitoring and load testing services

  validate            Validate ingress endpoints return healthy HTTP codes and UI content
                      Options:
                        --namespace <ns>  Target ingress namespace (default: monitoring)
                        --detailed        Include response previews for troubleshooting

  help                Show this help message

Examples:

  Deploy observability:
    ./observability.sh setup

  Skip helm initialization:
    ./observability.sh setup --skip-helm

  Check status:
    ./observability.sh status

  View Grafana logs:
    ./observability.sh logs --component grafana --follow

  Get access URLs:
    ./observability.sh url

  Validate ingress endpoints:
    ./observability.sh validate --detailed

EOF
}

# Function to run setup
run_setup() {
    local skip_helm=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-helm)
                skip_helm=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ ! -f "${OBSERVABILITY_DIR}/setup-prometheus-grafana.sh" ]; then
        print_error "Setup script not found at ${OBSERVABILITY_DIR}/setup-prometheus-grafana.sh"
        exit 1
    fi

    if [ "$skip_helm" = true ]; then
        "${OBSERVABILITY_DIR}/setup-prometheus-grafana.sh" --skip-helm
    else
        "${OBSERVABILITY_DIR}/setup-prometheus-grafana.sh"
    fi

    print_info "Documenting observability entry points..."
    generate_access_report
}

# Function to run cleanup
run_cleanup() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ ! -f "${OBSERVABILITY_DIR}/cleanup-observability.sh" ]; then
        print_error "Cleanup script not found at ${OBSERVABILITY_DIR}/cleanup-observability.sh"
        exit 1
    fi

    if [ "$force" = true ]; then
        "${OBSERVABILITY_DIR}/cleanup-observability.sh" --force
    else
        "${OBSERVABILITY_DIR}/cleanup-observability.sh"
    fi
}

# Function to show status
show_status() {
    print_section "Observability Stack Status"
    echo ""

    print_info "Checking namespace..."
    if kubectl get namespace "$NAMESPACE_MONITORING" &> /dev/null; then
        print_success "Namespace '$NAMESPACE_MONITORING' exists"
    else
        print_warning "Namespace '$NAMESPACE_MONITORING' does not exist"
        echo ""
        return
    fi

    echo ""
    print_info "Pod status:"
    kubectl get pods -n "$NAMESPACE_MONITORING" || print_warning "No pods found"

    echo ""
    print_info "Services:"
    kubectl get svc -n "$NAMESPACE_MONITORING" || print_warning "No services found"

    echo ""
    print_info "PersistentVolumeClaims:"
    kubectl get pvc -n "$NAMESPACE_MONITORING" || print_warning "No PVCs found"

    echo ""
    print_info "Helm Releases:"
    helm list -n "$NAMESPACE_MONITORING" || print_warning "No Helm releases found"
}

# Function to show logs
show_logs() {
    local component=""
    local follow=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --component)
                component="$2"
                shift 2
                ;;
            --follow)
                follow=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -z "$component" ]; then
        print_section "Available Components"
        kubectl get pods -n "$NAMESPACE_MONITORING" --no-headers | awk '{print "  -", $1}' || print_warning "No pods found"
        echo ""
        print_info "Usage: ./observability.sh logs --component <pod-name>"
        return
    fi

    if [ "$follow" = true ]; then
        print_info "Following logs for $component..."
        kubectl logs -n "$NAMESPACE_MONITORING" "$component" -f
    else
        kubectl logs -n "$NAMESPACE_MONITORING" "$component"
    fi
}

# Function to validate ingress endpoints
run_validation() {
    local namespace="$NAMESPACE_MONITORING"
    local detailed=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                namespace="$2"
                shift 2
                ;;
            --detailed)
                detailed=true
                shift
                ;;
            *)
                print_error "Unknown option for validate: $1"
                echo ""
                print_info "Usage: ./observability.sh validate [--namespace <ns>] [--detailed]"
                return 1
                ;;
        esac
    done

    local validation_script="${OBSERVABILITY_DIR}/validate-ingress.sh"
    if [ ! -f "$validation_script" ]; then
        print_error "Validation script not found at ${validation_script#$PROJECT_ROOT/}"
        return 1
    fi

    local -a args=(--namespace "$namespace")
    if [ "$detailed" = true ]; then
        args+=(--detailed)
    fi

    print_section "Ingress Endpoint Validation"
    print_info "Using LoadBalancer defined in namespace '$namespace'"
    echo ""

    bash "$validation_script" "${args[@]}"
}

# Function to get and display Ingress LoadBalancer URL
get_ingress_url() {
    load_observability_env

    local ingress_lb
    ingress_lb=$(get_loadbalancer_ip "ingress-nginx" "ingress-nginx-controller" || true)

    if [ -z "$ingress_lb" ]; then
        print_warning "Ingress LoadBalancer not ready yet"
        print_info "Check status with: kubectl get svc -n ingress-nginx ingress-nginx-controller"
        return 1
    fi

    print_success "Ingress LoadBalancer URL: http://${ingress_lb}"
    echo ""
    print_info "Available services:"
    echo "  • Grafana:        http://${ingress_lb}/grafana"
    echo "  • Prometheus:     http://${ingress_lb}/prometheus"
    echo "  • VictoriaMetrics: http://${ingress_lb}/victoria"
    echo "  • AlertManager:   http://${ingress_lb}/alertmanager"
    echo "  • Tempo:          http://${ingress_lb}/tempo"
    echo "  • Locust:         http://${ingress_lb}/locust"
    echo ""
    print_info "Grafana default credentials: admin / ${GRAFANA_ADMIN_PASSWORD:-admin123}"
}

# Main execution
main() {
    local command="${1:-help}"

    case "$command" in
        setup)
            shift
            run_setup "$@"
            ;;
        cleanup)
            shift
            run_cleanup "$@"
            ;;
        status)
            show_status
            ;;
        logs)
            shift
            show_logs "$@"
            ;;
        url|urls|access)
            get_ingress_url
            ;;
        validate)
            shift
            run_validation "$@"
            ;;
        help)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
