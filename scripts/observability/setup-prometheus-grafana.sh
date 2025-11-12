#!/bin/bash

################################################################################
#                                                                              #
#  Prometheus & Grafana Observability Setup Script                           #
#  Location: scripts/observability/setup-prometheus-grafana.sh               #
#                                                                              #
#  This script deploys Prometheus and Grafana to monitor a Locust cluster    #
#  on AWS EKS. Run this AFTER the main deployment (deploy.sh) is complete.  #
#                                                                              #
#  Prerequisites:                                                             #
#  - AWS EKS cluster already deployed                                        #
#  - kubectl configured and authenticated                                    #
#  - helm installed (v3.0+)                                                  #
#  - Locust namespace and workloads running                                  #
#                                                                              #
#  Usage:                                                                      #
#    ./setup-prometheus-grafana.sh                 # Deploy with defaults    #
#    ./setup-prometheus-grafana.sh --skip-helm    # Skip helm init          #
#                                                                              #
#  Total Time: ~5-10 minutes                                                  #
#                                                                              #
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source library functions
source "${PROJECT_ROOT}/scripts/common.sh"

# Configuration
NAMESPACE_MONITORING="monitoring"
PROMETHEUS_NAMESPACE="$NAMESPACE_MONITORING"
GRAFANA_NAMESPACE="$NAMESPACE_MONITORING"
LOCUST_NAMESPACE="locust"

# Helm chart versions
PROMETHEUS_CHART_VERSION="25.3.1"
GRAFANA_CHART_VERSION="7.0.8"

# Grafana configuration
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin123}"
GRAFANA_DOMAIN="${GRAFANA_DOMAIN:-grafana.local}"

# Parse arguments
SKIP_HELM_INIT=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-helm)
            SKIP_HELM_INIT=true
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
print_header "PROMETHEUS & GRAFANA OBSERVABILITY SETUP"
echo ""
print_info "Monitoring Namespace: $NAMESPACE_MONITORING"
print_info "Locust Namespace: $LOCUST_NAMESPACE"
print_info "Prometheus Version: $PROMETHEUS_CHART_VERSION"
print_info "Grafana Version: $GRAFANA_CHART_VERSION"
echo ""

# Record start time
START_TIME=$(date +%s)

# Function to check if helm is installed
check_helm() {
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed"
        print_info "Install helm from: https://helm.sh/docs/intro/install/"
        exit 1
    fi
    print_success "helm is installed: $(helm version --short)"
}

# Function to check kubectl connectivity
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Ensure kubectl is configured properly"
        exit 1
    fi
    CLUSTER_NAME=$(kubectl config current-context)
    print_success "Connected to cluster: $CLUSTER_NAME"
}

# Function to create monitoring namespace
create_namespace() {
    print_section "Creating Monitoring Namespace"

    if kubectl get namespace "$NAMESPACE_MONITORING" &> /dev/null; then
        print_warning "Namespace '$NAMESPACE_MONITORING' already exists"
    else
        kubectl create namespace "$NAMESPACE_MONITORING"
        kubectl label namespace "$NAMESPACE_MONITORING" name="$NAMESPACE_MONITORING"
        print_success "Namespace '$NAMESPACE_MONITORING' created"
    fi
    echo ""
}

# Function to add Prometheus Community Helm repo
add_helm_repos() {
    print_section "Adding Helm Repositories"

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    print_success "Helm repositories added and updated"
    echo ""
}

# Function to deploy Prometheus
deploy_prometheus() {
    print_section "Deploying Prometheus"

    # Create Prometheus values file
    cat > /tmp/prometheus-values.yaml <<EOF
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

    # Service Monitor for Prometheus to scrape its own metrics
    serviceMonitorSelectorNilUsesHelmValues: false

    # Pod Monitor for Prometheus to scrape pod metrics
    podMonitorSelectorNilUsesHelmValues: false

    # Additional scrape configs
    additionalScrapeConfigs:
      - job_name: 'locust-master'
        static_configs:
          - targets: ['locust-master-internal.locust.svc.cluster.local:8090']
        metrics_path: '/metrics'
        scrape_interval: 15s

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names:
                - locust
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__

prometheus-node-exporter:
  enabled: true

prometheus-pushgateway:
  enabled: false

grafana:
  enabled: true
  adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
  persistence:
    enabled: true
    size: 10Gi
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-operated:9090
          access: proxy
          isDefault: true
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      kubernetes-cluster:
        url: https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/charts/grafana/dashboards/kubernetes-cluster.json
      kubernetes-nodes:
        url: https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/charts/grafana/dashboards/kubernetes-nodes.json

alertmanager:
  enabled: true
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
    receivers:
      - name: 'default'

kubeStateMetrics:
  enabled: true

nodeExporter:
  enabled: true
EOF

    print_info "Installing kube-prometheus-stack (Prometheus + Grafana)..."

    helm upgrade --install prometheus-grafana \
        prometheus-community/kube-prometheus-stack \
        --namespace "$PROMETHEUS_NAMESPACE" \
        --values /tmp/prometheus-values.yaml \
        --version "$PROMETHEUS_CHART_VERSION" \
        --wait \
        --timeout 10m

    print_success "Prometheus and Grafana deployed successfully"
    echo ""
}

# Function to deploy custom Locust dashboards
deploy_locust_dashboards() {
    print_section "Deploying Locust Monitoring Dashboards"

    # Create ConfigMap with Locust dashboard
    cat > /tmp/locust-dashboard.json <<'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "datasource",
          "uid": "-- Grafana --"
        },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showThresholdLabels": false,
        "showThresholdMarkers": true
      },
      "pluginVersion": "10.0.0",
      "targets": [
        {
          "expr": "up{job=\"locust-master\"}",
          "refId": "A"
        }
      ],
      "title": "Locust Master Status",
      "type": "gauge"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "tooltip": false,
              "viz": false,
              "legend": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 3,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "mode": "single",
          "sort": "none"
        }
      },
      "targets": [
        {
          "expr": "container_memory_usage_bytes{pod=~\"locust-.*\",namespace=\"locust\"} / 1024 / 1024",
          "legendFormat": "{{pod}}",
          "refId": "A"
        }
      ],
      "title": "Locust Pods Memory Usage",
      "type": "timeseries"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["locust", "load-testing"],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Locust Load Testing Dashboard",
  "uid": "locust-dashboard",
  "version": 0,
  "weekStart": ""
}
EOF

    # Create ConfigMap
    kubectl create configmap locust-dashboard \
        --from-file=/tmp/locust-dashboard.json \
        -n "$GRAFANA_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Locust dashboard ConfigMap created"
    echo ""
}

# Function to setup port forwarding info
show_access_info() {
    print_section "Access Information"

    print_info "Prometheus:"
    print_status "  Port-forward: kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-grafana 9090:9090"
    print_status "  Access: http://localhost:9090"
    echo ""

    print_info "Grafana:"
    print_status "  Port-forward: kubectl port-forward -n $GRAFANA_NAMESPACE svc/prometheus-grafana 3000:80"
    print_status "  Access: http://localhost:3000"
    print_status "  Default credentials: admin / $GRAFANA_ADMIN_PASSWORD"
    echo ""

    print_warning "Note: Update GRAFANA_ADMIN_PASSWORD environment variable for production deployments"
    echo ""
}

# Function to verify deployment
verify_deployment() {
    print_section "Verifying Deployment"

    print_info "Checking Prometheus..."
    if kubectl get deployment prometheus-grafana-prometheus -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "Prometheus deployed successfully"
    else
        print_warning "Prometheus deployment still initializing..."
    fi

    print_info "Checking Grafana..."
    if kubectl get deployment prometheus-grafana -n "$GRAFANA_NAMESPACE" &> /dev/null; then
        print_success "Grafana deployed successfully"
    else
        print_warning "Grafana deployment still initializing..."
    fi

    print_info "Checking AlertManager..."
    if kubectl get statefulset prometheus-grafana-alertmanager -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "AlertManager deployed successfully"
    else
        print_warning "AlertManager deployment still initializing..."
    fi

    echo ""
    print_info "Pod status:"
    kubectl get pods -n "$PROMETHEUS_NAMESPACE" --no-headers | sed 's/^/  /'
    echo ""
}

# Function to register ServiceMonitor
apply_locust_servicemonitor() {
    print_section "Registering Locust ServiceMonitor"
    local monitor_file="${PROJECT_ROOT}/kubernetes/locust-servicemonitor.yaml"
    if [ ! -f "$monitor_file" ]; then
        print_warning "No ServiceMonitor manifest found. Create ${monitor_file} if you need Prometheus Operator scraping."
        echo ""
        return
    fi

    if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
        kubectl apply -f "$monitor_file"
        print_success "Locust ServiceMonitor applied"
    else
        print_warning "ServiceMonitor CRD not yet available. Re-run this script after CRD installation."
    fi
    echo ""
}

# Function to save configuration
save_configuration() {
    print_section "Saving Configuration"

    cat > "${PROJECT_ROOT}/.env.observability" <<EOF
# Observability Configuration
PROMETHEUS_NAMESPACE=$PROMETHEUS_NAMESPACE
GRAFANA_NAMESPACE=$GRAFANA_NAMESPACE
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD
GRAFANA_DOMAIN=$GRAFANA_DOMAIN
LOCUST_NAMESPACE=$LOCUST_NAMESPACE
EOF

    print_success "Configuration saved to .env.observability"
    echo ""
}

# Main execution
main() {
    print_info "Phase 1/7: Checking Prerequisites..."
    check_helm
    check_kubectl
    echo ""

    print_info "Phase 2/7: Creating Monitoring Namespace..."
    create_namespace

    if [ "$SKIP_HELM_INIT" = false ]; then
        print_info "Phase 3/7: Adding Helm Repositories..."
        add_helm_repos
    else
        print_warning "Skipping Helm repository setup..."
        echo ""
    fi

    print_info "Phase 4/7: Deploying Prometheus and Grafana..."
    deploy_prometheus

    print_info "Phase 5/7: Registering Locust metrics..."
    apply_locust_servicemonitor

    print_info "Phase 6/7: Deploying Locust Dashboards..."
    deploy_locust_dashboards

    print_info "Phase 7/7: Saving Configuration..."
    save_configuration

    # Calculate total time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))

    # Final summary
    print_header "OBSERVABILITY SETUP COMPLETE!"
    echo ""
    print_section "Summary"
    print_success "All observability components deployed successfully"
    print_info "Total setup time: ${MINUTES}m ${SECONDS}s"
    echo ""

    show_access_info

    print_section "Next Steps"
    print_step "1. Wait 2-3 minutes for all pods to be ready"
    print_step "2. Port-forward Grafana: kubectl port-forward -n $GRAFANA_NAMESPACE svc/prometheus-grafana 3000:80"
    print_step "3. Access Grafana at http://localhost:3000"
    print_step "4. Login with admin / $GRAFANA_ADMIN_PASSWORD"
    print_step "5. Add Prometheus datasource (usually auto-configured)"
    print_step "6. Import Locust dashboard"
    print_step "7. Monitor your load tests in real-time"
    echo ""

    verify_deployment

    print_section "Useful Commands"
    echo ""
    print_status "View all monitoring pods:"
    print_info "  kubectl get pods -n $PROMETHEUS_NAMESPACE"
    echo ""
    print_status "View Prometheus logs:"
    print_info "  kubectl logs -n $PROMETHEUS_NAMESPACE -l app.kubernetes.io/name=prometheus"
    echo ""
    print_status "View Grafana logs:"
    print_info "  kubectl logs -n $GRAFANA_NAMESPACE -l app.kubernetes.io/name=grafana"
    echo ""
    print_status "Check Prometheus targets:"
    print_info "  kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-grafana 9090:9090"
    print_info "  Then visit: http://localhost:9090/targets"
    echo ""

    print_section "Cleanup"
    print_warning "To remove observability stack, run:"
    echo ""
    print_status "  helm uninstall prometheus-grafana -n $PROMETHEUS_NAMESPACE"
    print_status "  kubectl delete namespace $PROMETHEUS_NAMESPACE"
    echo ""

    print_success "Observability setup completed successfully!"
}

# Execute main function
main
