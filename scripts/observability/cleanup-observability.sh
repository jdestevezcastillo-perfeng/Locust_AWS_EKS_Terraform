#!/bin/bash

################################################################################
#                                                                              #
#  Observability Cleanup Script                                              #
#  Location: scripts/observability/cleanup-observability.sh                  #
#                                                                              #
#  This script removes Prometheus, Grafana, and related monitoring            #
#  infrastructure from the Kubernetes cluster.                               #
#                                                                              #
#  Usage:                                                                      #
#    ./cleanup-observability.sh              # Interactive cleanup            #
#    ./cleanup-observability.sh --force      # Force cleanup without prompts  #
#                                                                              #
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library functions
source "${PROJECT_ROOT}/scripts/common.sh"

# Configuration
NAMESPACE_MONITORING="monitoring"
FORCE_CLEANUP=false
PROM_HELM_RELEASE="prometheus-grafana"
VICTORIA_HELM_RELEASE="victoria-metrics"
LOKI_HELM_RELEASE="loki"
TEMPO_HELM_RELEASE="tempo"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Display banner
clear
print_header "OBSERVABILITY CLEANUP"
echo ""
print_warning "This will remove Prometheus, Grafana, VictoriaMetrics, Loki, Tempo, and all monitoring infrastructure"
echo ""

# Confirm deletion
if [ "$FORCE_CLEANUP" = false ]; then
    print_info "Monitoring Namespace: $NAMESPACE_MONITORING"
    echo ""
    print_warning "Are you sure you want to proceed? (yes/no)"
    read -r CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
fi

echo ""
print_section "Removing Observability Components"

remove_release() {
    local release=$1
    if helm status "$release" -n "$NAMESPACE_MONITORING" &>/dev/null; then
        helm uninstall "$release" -n "$NAMESPACE_MONITORING"
        print_success "Helm release '$release' removed"
    else
        print_warning "Helm release '$release' not found"
    fi
}

print_info "Removing Helm releases..."
remove_release "$PROM_HELM_RELEASE"
remove_release "$VICTORIA_HELM_RELEASE"
remove_release "$LOKI_HELM_RELEASE"
remove_release "$TEMPO_HELM_RELEASE"

echo ""

# Remove monitoring manifests
print_info "Cleaning up Kubernetes monitoring manifests..."
if [ -d "${PROJECT_ROOT}/kubernetes/overlays/monitoring" ]; then
    rm -rf "${PROJECT_ROOT}/kubernetes/overlays/monitoring"
    print_success "Kubernetes monitoring manifests removed"
fi

echo ""

# Remove namespace
print_info "Removing monitoring namespace..."
if kubectl get namespace "$NAMESPACE_MONITORING" &> /dev/null; then
    kubectl delete namespace "$NAMESPACE_MONITORING" --ignore-not-found
    print_success "Namespace removed"
else
    print_warning "Monitoring namespace not found"
fi

echo ""

# Remove configuration file
print_info "Removing configuration file..."
if [ -f "${PROJECT_ROOT}/.env.observability" ]; then
    rm -f "${PROJECT_ROOT}/.env.observability"
    print_success "Configuration file removed"
fi

echo ""

# Final summary
print_header "CLEANUP COMPLETE!"
echo ""
print_success "All observability components have been removed"
echo ""
