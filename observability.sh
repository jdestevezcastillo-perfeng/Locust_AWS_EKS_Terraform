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
#    ./observability.sh cleanup            # Remove observability stack      #
#    ./observability.sh status             # Check observability status      #
#    ./observability.sh logs               # View pod logs                    #
#    ./observability.sh port-forward       # Setup port forwarding           #
#    ./observability.sh help               # Show this help message          #
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

    local grafana_namespace="${GRAFANA_NAMESPACE:-$NAMESPACE_MONITORING}"
    local prometheus_namespace="${PROMETHEUS_NAMESPACE:-$NAMESPACE_MONITORING}"
    local locust_namespace="${LOCUST_NAMESPACE:-locust}"
    local grafana_password="${GRAFANA_ADMIN_PASSWORD:-admin123}"

    local grafana_port_forward="kubectl port-forward -n ${grafana_namespace} svc/${PROM_HELM_RELEASE} 3000:80"
    local prometheus_port_forward="kubectl port-forward -n ${prometheus_namespace} svc/${PROM_SERVICE_NAME} 9090:9090"
    local victoria_port_forward="kubectl port-forward -n ${prometheus_namespace} svc/${VICTORIA_HELM_RELEASE}-victoria-metrics-single-server 8428:8428"
    local loki_port_forward="kubectl port-forward -n ${prometheus_namespace} svc/${LOKI_HELM_RELEASE}-loki 3100:3100"
    local tempo_port_forward="kubectl port-forward -n ${prometheus_namespace} svc/${TEMPO_HELM_RELEASE}-tempo 3200:3200"

    local locust_host
    locust_host=$(get_loadbalancer_ip "$locust_namespace" "locust-master" || true)
    local locust_url locust_note
    if [ -n "$locust_host" ]; then
        locust_url="http://${locust_host}:8089"
        locust_note="Public LoadBalancer for service 'locust-master' in namespace ${locust_namespace}."
    else
        locust_url="(pending)"
        locust_note="LoadBalancer not ready yet. Check with 'kubectl get svc -n ${locust_namespace} locust-master'."
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    mkdir -p "${PROJECT_ROOT}/reports"

    cat > "$ACCESS_REPORT_FILE" <<EOF
# Observability Access Links

_Last updated: ${timestamp}_

| Service | URL | Notes |
| --- | --- | --- |
| Grafana | http://localhost:3000 | Port-forward: \`${grafana_port_forward}\`. Credentials: admin / ${grafana_password}. |
| Prometheus | http://localhost:9090 | Port-forward: \`${prometheus_port_forward}\`. Targets view: \`http://localhost:9090/targets\`. |
| Locust UI | ${locust_url} | ${locust_note} |
| VictoriaMetrics | http://localhost:8428 | Port-forward: \`${victoria_port_forward}\`. Query path: \`/select/\`. |
| Loki | http://localhost:3100 | Port-forward: \`${loki_port_forward}\`. Explore log queries via Grafana datasource `Loki`. |
| Tempo | http://localhost:3200 | Port-forward: \`${tempo_port_forward}\`. Grafana datasource `Tempo`. |
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

  port-forward        Setup port forwarding for accessing services
                      Options:
                        --prometheus   Forward only Prometheus (port 9090)
                        --grafana      Forward only Grafana (port 3000)
                        --both         Forward both (default)

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

  Port forward Grafana:
    ./observability.sh port-forward --grafana

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

# Function to setup port forwarding
setup_port_forwarding() {
    local prometheus=true
    local grafana=true

    while [[ $# -gt 0 ]]; do
        case $1 in
            --prometheus)
                prometheus=true
                grafana=false
                shift
                ;;
            --grafana)
                prometheus=false
                grafana=true
                shift
                ;;
            --both)
                prometheus=true
                grafana=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ "$prometheus" = true ]; then
        print_info "Setting up port forwarding for Prometheus..."
        print_status "kubectl port-forward -n $NAMESPACE_MONITORING svc/prometheus-grafana 9090:9090"
        print_info "Access: http://localhost:9090"
        echo ""
    fi

    if [ "$grafana" = true ]; then
        print_info "Setting up port forwarding for Grafana..."
        print_status "kubectl port-forward -n $NAMESPACE_MONITORING svc/prometheus-grafana 3000:80"
        print_info "Access: http://localhost:3000"
        print_info "Default credentials: admin / admin123"
        echo ""
    fi

    if [ "$prometheus" = true ] && [ "$grafana" = true ]; then
        print_warning "Run these commands in separate terminals"
    fi
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
        port-forward)
            shift
            setup_port_forwarding "$@"
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
