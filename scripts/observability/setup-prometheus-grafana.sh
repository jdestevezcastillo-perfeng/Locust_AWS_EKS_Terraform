#!/bin/bash

################################################################################
#                                                                              #
#  Observability Setup Script                                                 #
#  Location: scripts/observability/setup-prometheus-grafana.sh               #
#                                                                              #
#  This script deploys Prometheus, Grafana, VictoriaMetrics, Loki, and Tempo #
#  to monitor a Locust cluster on AWS EKS. Run this AFTER deploy.sh.         #
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
PROMETHEUS_CHART_VERSION="79.5.0"
GRAFANA_CHART_VERSION="7.0.8"
VICTORIA_CHART_VERSION="0.25.4"
LOKI_CHART_VERSION="2.10.3"
TEMPO_CHART_VERSION="1.24.0"

PROM_HELM_RELEASE="prometheus-grafana"
VICTORIA_HELM_RELEASE="victoria-metrics"
LOKI_HELM_RELEASE="loki"
TEMPO_HELM_RELEASE="tempo"
PROM_SERVICE_NAME="${PROM_HELM_RELEASE}-kube-prometheus-prometheus"

# VictoriaMetrics resource overrides
VICTORIA_CPU_REQUEST="${VICTORIA_CPU_REQUEST:-500m}"
VICTORIA_MEMORY_REQUEST="${VICTORIA_MEMORY_REQUEST:-512Mi}"
VICTORIA_CPU_LIMIT="${VICTORIA_CPU_LIMIT:-2}"
VICTORIA_MEMORY_LIMIT="${VICTORIA_MEMORY_LIMIT:-2Gi}"

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

get_tf_output() {
    local output_name=$1
    terraform -chdir="${PROJECT_ROOT}/terraform" output -raw "$output_name" 2>/dev/null || echo ""
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
    helm repo add victoria-metrics https://victoriametrics.github.io/helm-charts
    helm repo update

    print_success "Helm repositories added and updated"
    echo ""
}

# Function to deploy AWS Cluster Autoscaler
deploy_cluster_autoscaler() {
    print_section "Deploying AWS Cluster Autoscaler"

    # Get cluster name from Terraform output
    local cluster_name
    cluster_name=$(get_tf_output "cluster_name")

    if [ -z "$cluster_name" ]; then
        print_warning "Could not retrieve cluster name from Terraform. Using default from config..."
        cluster_name="${CLUSTER_NAME:-locust-dev-cluster}"
    fi

    print_info "Deploying Cluster Autoscaler for cluster: $cluster_name"

    # Create Cluster Autoscaler deployment
    cat > /tmp/cluster-autoscaler.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["events", "endpoints"]
    verbs: ["create", "patch"]
  - apiGroups: [""]
    resources: ["pods/eviction"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["update"]
  - apiGroups: [""]
    resources: ["endpoints"]
    resourceNames: ["cluster-autoscaler"]
    verbs: ["get", "update"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["watch", "list", "get", "update"]
  - apiGroups: [""]
    resources:
      - "namespaces"
      - "pods"
      - "services"
      - "replicationcontrollers"
      - "persistentvolumeclaims"
      - "persistentvolumes"
    verbs: ["watch", "list", "get"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes", "csidrivers", "csistoragecapacities"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["batch", "extensions"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["create"]
  - apiGroups: ["coordination.k8s.io"]
    resourceNames: ["cluster-autoscaler"]
    resources: ["leases"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    verbs: ["delete", "get", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      priorityClassName: system-cluster-critical
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
      serviceAccountName: cluster-autoscaler
      containers:
        - image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.31.0
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 600Mi
            requests:
              cpu: 100m
              memory: 600Mi
          command:
            - ./cluster-autoscaler
            - --v=4
            - --stderrthreshold=info
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --expander=least-waste
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${cluster_name}
            - --balance-similar-node-groups
            - --skip-nodes-with-system-pods=false
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs/ca-certificates.crt
              readOnly: true
          imagePullPolicy: Always
      volumes:
        - name: ssl-certs
          hostPath:
            path: /etc/ssl/certs/ca-bundle.crt
      nodeSelector:
        workload: monitoring
      tolerations:
        - key: workload
          operator: Equal
          value: monitoring
          effect: NoSchedule
EOF

    kubectl apply -f /tmp/cluster-autoscaler.yaml

    print_success "Cluster Autoscaler deployed"
    print_info "The autoscaler will automatically scale node groups based on pod pending state"
    echo ""
}

# Function to deploy nginx Ingress Controller
deploy_nginx_ingress() {
    print_section "Deploying nginx Ingress Controller"

    # Add nginx Ingress Helm repo if not already added
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
    helm repo update

    # Create nginx Ingress values
    cat > /tmp/nginx-ingress-values.yaml <<'EOF'
controller:
  service:
    type: LoadBalancer
  nodeSelector:
    workload: monitoring
  tolerations:
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
  # Enable metrics for Prometheus scraping
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  # Configure admission webhooks with tolerations for tainted nodes
  admissionWebhooks:
    patch:
      nodeSelector:
        workload: monitoring
      tolerations:
        - key: workload
          operator: Equal
          value: monitoring
          effect: NoSchedule
EOF

    print_info "Installing nginx Ingress Controller..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --values /tmp/nginx-ingress-values.yaml \
        --wait --timeout 5m

    print_success "nginx Ingress Controller deployed"
    print_info "Single LoadBalancer created for all monitoring tools"
    echo ""
}

# Function to deploy Prometheus
deploy_victoriametrics() {
    print_section "Deploying VictoriaMetrics (long-term metrics storage)"

    local victoriametrics_role_arn
    victoriametrics_role_arn=$(get_tf_output "victoriametrics_role_arn")

    local victoriametrics_storage_class
    victoriametrics_storage_class="${VICTORIA_STORAGE_CLASS:-}"

    if [ -z "$victoriametrics_storage_class" ]; then
        victoriametrics_storage_class=$(kubectl get storageclass \
            -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null | awk 'NF {print $1; exit}' || true)
    fi

    if [ -z "$victoriametrics_storage_class" ]; then
        victoriametrics_storage_class=$(kubectl get storageclass \
            -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null | awk 'NF {print $1; exit}' || true)
    fi

    local available_storage_classes
    available_storage_classes=$(kubectl get storageclass \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null | awk 'NF' || true)

    if [ -z "$victoriametrics_storage_class" ] && [ -n "$available_storage_classes" ]; then
        if printf '%s\n' "$available_storage_classes" | grep -Fxq "gp3"; then
            victoriametrics_storage_class="gp3"
            print_info "No default StorageClass detected; preferring 'gp3'. Export VICTORIA_STORAGE_CLASS to override."
        fi
    fi

    if [ -z "$victoriametrics_storage_class" ] && [ -n "$available_storage_classes" ]; then
        local storage_class_count
        storage_class_count=$(printf '%s\n' "$available_storage_classes" | wc -l | tr -d '[:space:]')

        if [ "$storage_class_count" -eq 1 ]; then
            victoriametrics_storage_class=$(printf '%s\n' "$available_storage_classes")
            print_warning "No default StorageClass detected; using '${victoriametrics_storage_class}'. Export VICTORIA_STORAGE_CLASS to override."
        else
            for candidate in gp3 gp3-csi gp2 gp2-csi gp-standard gp2-standard gp3-standard ebs-sc standard; do
                if printf '%s\n' "$available_storage_classes" | grep -Fxq "$candidate"; then
                    victoriametrics_storage_class="$candidate"
                    print_warning "No default StorageClass detected; falling back to '${victoriametrics_storage_class}'. Export VICTORIA_STORAGE_CLASS to override."
                    break
                fi
            done

            if [ -z "$victoriametrics_storage_class" ]; then
                victoriametrics_storage_class=$(printf '%s\n' "$available_storage_classes" | head -n 1)
                print_warning "No default StorageClass detected; selecting first available '${victoriametrics_storage_class}'. Export VICTORIA_STORAGE_CLASS to choose explicitly."
            fi
        fi
    fi

    if [ -z "$victoriametrics_storage_class" ]; then
        print_error "Unable to detect a default StorageClass for VictoriaMetrics PVC."
        if [ -n "$available_storage_classes" ]; then
            print_info "Detected StorageClasses:"
            printf '  - %s\n' $available_storage_classes
        fi
        print_info "Set VICTORIA_STORAGE_CLASS or label a StorageClass as default and re-run the setup."
        exit 1
    fi

    print_info "Using storage class '${victoriametrics_storage_class}' for VictoriaMetrics PVC"

    cat > /tmp/victoriametrics-values.yaml <<EOF
serviceAccount:
  create: true
  name: victoriametrics
EOF

    if [ -n "$victoriametrics_role_arn" ]; then
        cat >> /tmp/victoriametrics-values.yaml <<EOF
  annotations:
    eks.amazonaws.com/role-arn: "${victoriametrics_role_arn}"
EOF
    else
        cat >> /tmp/victoriametrics-values.yaml <<'EOF'
  annotations: {}
EOF
        print_warning "victoriametrics_role_arn Terraform output not found; continuing without IRSA."
    fi

    cat >> /tmp/victoriametrics-values.yaml <<EOF
server:
  service:
    type: ClusterIP
  retentionPeriod: 90d
  resources:
    requests:
      cpu: ${VICTORIA_CPU_REQUEST}
      memory: ${VICTORIA_MEMORY_REQUEST}
    limits:
      cpu: "${VICTORIA_CPU_LIMIT}"
      memory: ${VICTORIA_MEMORY_LIMIT}
  persistentVolume:
    enabled: true
    size: 100Gi
    storageClassName: "${victoriametrics_storage_class}"
  nodeSelector:
    workload: monitoring
  tolerations:
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule
EOF

    helm upgrade --install "$VICTORIA_HELM_RELEASE" \
        victoria-metrics/victoria-metrics-single \
        --namespace "$PROMETHEUS_NAMESPACE" \
        --version "$VICTORIA_CHART_VERSION" \
        --values /tmp/victoriametrics-values.yaml \
        --wait --timeout 10m

    print_success "VictoriaMetrics release deployed"
    echo ""
}

deploy_prometheus() {
    print_section "Deploying Prometheus"

    # Create Prometheus values file
    cat > /tmp/prometheus-values.yaml <<EOF
prometheus:
  service:
    type: ClusterIP
  prometheusSpec:
    retention: 30d
    # Configure Prometheus to work behind /prometheus subpath
    externalUrl: http://INGRESS_HOSTNAME/prometheus
    routePrefix: /
    nodeSelector:
      workload: monitoring
    tolerations:
      - key: workload
        operator: Equal
        value: monitoring
        effect: NoSchedule
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
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
            replacement: \$1:\$2
            target_label: __address__
    remoteWrite:
      - url: "http://$VICTORIA_HELM_RELEASE-victoria-metrics-single-server.$PROMETHEUS_NAMESPACE.svc.cluster.local:8428/api/v1/write"
        writeRelabelConfigs: []
        queueConfig:
          capacity: 50000
          maxShards: 4
          maxSamplesPerSend: 10000

prometheus-node-exporter:
  enabled: true
  # DaemonSet runs on all nodes, so add tolerations for both taints
  tolerations:
    - key: workload
      operator: Equal
      value: locust
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule

prometheus-pushgateway:
  enabled: false

grafana:
  enabled: true
  adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
  # Configure Grafana to work behind /grafana subpath
  grafana.ini:
    server:
      root_url: "%(protocol)s://%(domain)s/grafana"
      serve_from_sub_path: true
  nodeSelector:
    workload: monitoring
  tolerations:
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule
  # Admission webhook job also needs tolerations
  admissionWebhooks:
    patch:
      nodeSelector:
        workload: monitoring
      tolerations:
        - key: workload
          operator: Equal
          value: monitoring
          effect: NoSchedule
  service:
    type: ClusterIP
    port: 80
  sidecar:
    datasources:
      enabled: true
  additionalDataSources:
    - name: VictoriaMetrics
      uid: victoria-metrics
      type: prometheus
      access: proxy
      url: "http://$VICTORIA_HELM_RELEASE-victoria-metrics-single-server.$PROMETHEUS_NAMESPACE.svc.cluster.local:8428"
      isDefault: false
      jsonData:
        timeInterval: 30s
    - name: Loki
      uid: loki
      type: loki
      access: proxy
      url: "http://$LOKI_HELM_RELEASE-loki.$PROMETHEUS_NAMESPACE.svc.cluster.local:3100"
      isDefault: false
    - name: Tempo
      uid: tempo
      type: tempo
      access: proxy
      url: "http://$TEMPO_HELM_RELEASE-tempo.$PROMETHEUS_NAMESPACE.svc.cluster.local:3200"
      jsonData:
        httpMethod: GET
        tracesToLogs:
          datasourceUid: loki
  persistence:
    enabled: true
    size: 10Gi
    storageClassName: gp2
  # Datasources are auto-configured by kube-prometheus-stack
  # No need to explicitly define them to avoid conflicts
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
        gnetId: 6417
        revision: 1
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 15760
        revision: 1
        datasource: Prometheus
      k8s-dashboard:
        gnetId: 15661
        revision: 1
        datasource: Prometheus

alertmanager:
  enabled: true
  service:
    type: ClusterIP
  alertmanagerSpec:
    # Configure AlertManager to work behind /alertmanager subpath
    externalUrl: http://INGRESS_HOSTNAME/alertmanager
    routePrefix: /
    nodeSelector:
      workload: monitoring
    tolerations:
      - key: workload
        operator: Equal
        value: monitoring
        effect: NoSchedule
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

kube-state-metrics:
  nodeSelector:
    workload: monitoring
  tolerations:
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule

nodeExporter:
  enabled: true
  # DaemonSet runs on all nodes, so add tolerations for both taints
  tolerations:
    - key: workload
      operator: Equal
      value: locust
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule

# Prometheus Operator needs tolerations
prometheusOperator:
  nodeSelector:
    workload: monitoring
  tolerations:
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule
  admissionWebhooks:
    patch:
      nodeSelector:
        workload: monitoring
      tolerations:
        - key: workload
          operator: Equal
          value: monitoring
          effect: NoSchedule
EOF

    print_info "Installing kube-prometheus-stack (Prometheus + Grafana)..."
    print_warning "This may take 5-15 minutes. Monitoring progress..."
    echo ""

    # Run helm install in background
    helm upgrade --install "$PROM_HELM_RELEASE" \
        prometheus-community/kube-prometheus-stack \
        --namespace "$PROMETHEUS_NAMESPACE" \
        --values /tmp/prometheus-values.yaml \
        --version "$PROMETHEUS_CHART_VERSION" \
        --wait \
        --timeout 15m > /tmp/helm-install.log 2>&1 &

    HELM_PID=$!

    # Give helm a moment to start
    sleep 2

    # Verify the process started
    if ! kill -0 $HELM_PID 2>/dev/null; then
        print_error "Helm process failed to start or exited immediately"
        cat /tmp/helm-install.log
        exit 1
    fi

    # Monitor progress while helm is running
    print_info "Monitoring pod deployment progress (PID: $HELM_PID)..."
    echo ""

    local last_status=""
    local iteration=0
    while true; do
        # Check if helm process is still running
        if ! kill -0 $HELM_PID 2>/dev/null; then
            break
        fi
        # Get pod status summary
        local pod_info
        pod_info=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" 2>/dev/null | tail -n +2 | awk '{print $3}' | sort | uniq -c | tr '\n' ' ')

        # Get running/total pod count
        local total_pods ready_pods
        total_pods=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" --no-headers 2>/dev/null | wc -l)
        ready_pods=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" --no-headers 2>/dev/null | grep "Running" | awk '{print $2}' | awk -F'/' '$1==$2' | wc -l)

        if [[ "$pod_info" != "$last_status" && -n "$pod_info" ]]; then
            local timestamp
            timestamp=$(date +"%H:%M:%S")
            echo ""
            print_status "[$timestamp] Ready: $ready_pods/$total_pods pods | Status: $pod_info"
            last_status="$pod_info"
        elif [ $((iteration % 6)) -eq 0 ]; then
            # Show heartbeat every 30 seconds even if no change
            echo -ne "."
        fi

        iteration=$((iteration + 1))
        sleep 5
    done

    # Wait for helm to complete and check exit status
    wait $HELM_PID
    HELM_EXIT_CODE=$?

    echo ""
    echo ""

    if [ $HELM_EXIT_CODE -eq 0 ]; then
        print_success "Helm installation completed successfully"

        # Show final pod status
        print_info "Final pod status:"
        kubectl get pods -n "$PROMETHEUS_NAMESPACE" -o wide 2>/dev/null | sed 's/^/  /'
        echo ""

        print_success "Prometheus and Grafana deployed successfully"
    else
        print_error "Helm installation failed or timed out"
        echo ""
        print_info "Current pod status:"
        kubectl get pods -n "$PROMETHEUS_NAMESPACE" 2>/dev/null | sed 's/^/  /'
        echo ""
        print_info "Helm installation logs:"
        cat /tmp/helm-install.log
        echo ""
        print_warning "You can check pod logs with: kubectl logs -n $PROMETHEUS_NAMESPACE <pod-name>"
        exit 1
    fi
    echo ""
}

deploy_loki() {
    print_section "Deploying Loki (logs)"

    cat > /tmp/loki-values.yaml <<'EOF'
loki:
  persistence:
    enabled: true
    size: 50Gi
    storageClassName: gp2
  nodeSelector:
    workload: monitoring
  tolerations:
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule
prometheus:
  enabled: false
grafana:
  enabled: false
fluent-bit:
  enabled: false
promtail:
  enabled: true
  # Promtail is a DaemonSet that collects logs from all nodes
  tolerations:
    - key: workload
      operator: Equal
      value: locust
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: monitoring
      effect: NoSchedule
  pipelineStages: []
  extraScrapeConfigs: []
EOF

    helm upgrade --install "$LOKI_HELM_RELEASE" \
        grafana/loki-stack \
        --namespace "$PROMETHEUS_NAMESPACE" \
        --version "$LOKI_CHART_VERSION" \
        --values /tmp/loki-values.yaml \
        --wait --timeout 10m

    print_success "Loki release deployed"
    echo ""
}

deploy_tempo() {
    print_section "Deploying Tempo (traces)"

    cat > /tmp/tempo-values.yaml <<'EOF'
persistence:
  enabled: true
  size: 40Gi
  storageClassName: gp2
# Node selector and tolerations at top level for Tempo pods
nodeSelector:
  workload: monitoring
tolerations:
  - key: workload
    operator: Equal
    value: monitoring
    effect: NoSchedule
tempo:
  retention: 168h
tempoQuery:
  enabled: true
  service:
    type: ClusterIP
    port: 16686
EOF

    helm upgrade --install "$TEMPO_HELM_RELEASE" \
        grafana/tempo \
        --namespace "$PROMETHEUS_NAMESPACE" \
        --version "$TEMPO_CHART_VERSION" \
        --values /tmp/tempo-values.yaml \
        --wait --timeout 10m

    print_success "Tempo release deployed"
    echo ""
}

# Function to deploy Ingress resources for monitoring tools
deploy_ingress() {
    print_section "Deploying Ingress for Monitoring Tools"

    # Create Ingress resource
    cat > /tmp/monitoring-ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
  namespace: monitoring
  annotations:
    # Strip path prefix before forwarding to backend
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    # Set larger timeouts for long-running queries
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      # Grafana - Dashboard UI
      - path: /grafana(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: prometheus-grafana-grafana
            port:
              number: 80
      # Prometheus - Metrics query UI
      - path: /prometheus(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: prometheus-grafana-kube-pr-prometheus
            port:
              number: 9090
      # VictoriaMetrics - Long-term metrics storage UI
      - path: /victoria(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: victoria-metrics-victoria-metrics-single-server
            port:
              number: 8428
      # AlertManager - Alert management UI
      - path: /alertmanager(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: prometheus-grafana-kube-pr-alertmanager
            port:
              number: 9093
      # Tempo - Distributed tracing UI
      - path: /tempo(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: tempo-tempo-query
            port:
              number: 16686
EOF

    # Apply Ingress resource
    kubectl apply -f /tmp/monitoring-ingress.yaml

    print_success "Ingress resource deployed"
    print_info "All monitoring tools accessible via single LoadBalancer URL with different paths"
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

# Function to get Ingress LoadBalancer hostname
get_ingress_url() {
    # Wait a moment for LoadBalancer to provision
    sleep 3

    local hostname=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

    if [ -z "$hostname" ] || [ "$hostname" = "null" ]; then
        echo "pending"
    else
        echo "http://${hostname}"
    fi
}

# Function to show Ingress access information
show_access_info() {
    print_section "nginx Ingress Access URLs"

    print_info "Fetching Ingress LoadBalancer URL (this may take 1-2 minutes for AWS to provision)..."
    echo ""

    INGRESS_BASE_URL=$(get_ingress_url)

    if [ "$INGRESS_BASE_URL" = "pending" ]; then
        print_warning "Ingress LoadBalancer still provisioning..."
        print_status "  Check status: kubectl get svc -n ingress-nginx ingress-nginx-controller -w"
        echo ""
        print_info "Once ready, access monitoring tools at:"
    else
        print_success "Ingress LoadBalancer ready!"
        echo ""
        print_info "Access all monitoring tools via single LoadBalancer URL:"
    fi

    echo ""
    print_info "Grafana (Dashboards & Visualization):"
    print_status "  URL: ${INGRESS_BASE_URL}/grafana"
    print_status "  Credentials: admin / $GRAFANA_ADMIN_PASSWORD"
    echo ""

    print_info "Prometheus (Metrics Query & Browser):"
    print_status "  URL: ${INGRESS_BASE_URL}/prometheus"
    echo ""

    print_info "VictoriaMetrics (Long-term Metrics Storage):"
    print_status "  URL: ${INGRESS_BASE_URL}/victoria"
    echo ""

    print_info "AlertManager (Alert Management):"
    print_status "  URL: ${INGRESS_BASE_URL}/alertmanager"
    echo ""

    print_info "Tempo (Distributed Tracing UI):"
    print_status "  URL: ${INGRESS_BASE_URL}/tempo"
    echo ""

    print_info "Loki (Logs - API only, access via Grafana datasource):"
    print_status "  Internal: http://$LOKI_HELM_RELEASE-loki.$PROMETHEUS_NAMESPACE.svc.cluster.local:3100"
    echo ""

    print_info "Locust (Load Testing UI - Separate LoadBalancer):"
    LOCUST_URL=$(kubectl get svc -n locust locust-master -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$LOCUST_URL" ] && [ "$LOCUST_URL" != "null" ]; then
        print_status "  URL: http://${LOCUST_URL}:8089"
    else
        print_status "  URL: pending (run: kubectl get svc -n locust locust-master -w)"
    fi
    echo ""

    print_warning "💰 Cost Savings: Using 1 nginx LoadBalancer instead of 5 separate LoadBalancers (~\$72/month saved!)"
    print_warning "🔒 Security: All services are publicly accessible. Restrict access via AWS security groups for production!"
    print_warning "🔑 Update GRAFANA_ADMIN_PASSWORD for production deployments (current: $GRAFANA_ADMIN_PASSWORD)"
    echo ""
}

# Function to verify deployment
verify_deployment() {
    print_section "Verifying Deployment"

    print_info "Checking Prometheus..."
    if kubectl get deployment $PROM_HELM_RELEASE-prometheus -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "Prometheus deployed successfully"
    else
        print_warning "Prometheus deployment still initializing..."
    fi

    print_info "Checking Grafana..."
    if kubectl get deployment $PROM_HELM_RELEASE -n "$GRAFANA_NAMESPACE" &> /dev/null; then
        print_success "Grafana deployed successfully"
    else
        print_warning "Grafana deployment still initializing..."
    fi

    print_info "Checking AlertManager..."
    if kubectl get statefulset $PROM_HELM_RELEASE-alertmanager -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "AlertManager deployed successfully"
    else
        print_warning "AlertManager deployment still initializing..."
    fi

    print_info "Checking VictoriaMetrics..."
    if kubectl get statefulset $VICTORIA_HELM_RELEASE-victoria-metrics-single-server -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "VictoriaMetrics deployed successfully"
    else
        print_warning "VictoriaMetrics statefulset still initializing..."
    fi

    print_info "Checking Loki..."
    if kubectl get statefulset $LOKI_HELM_RELEASE-loki -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "Loki deployed successfully"
    else
        print_warning "Loki statefulset still initializing..."
    fi

    print_info "Checking Tempo..."
    if kubectl get statefulset $TEMPO_HELM_RELEASE-tempo -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        print_success "Tempo deployed successfully"
    else
        print_warning "Tempo statefulset still initializing..."
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
    print_info "Phase 1/13: Checking Prerequisites..."
    check_helm
    check_kubectl
    echo ""

    print_info "Phase 2/13: Creating Monitoring Namespace..."
    create_namespace

    if [ "$SKIP_HELM_INIT" = false ]; then
        print_info "Phase 3/13: Adding Helm Repositories..."
        add_helm_repos
    else
        print_warning "Skipping Helm repository setup..."
        echo ""
    fi

    print_info "Phase 4/13: Deploying AWS Cluster Autoscaler..."
    deploy_cluster_autoscaler

    print_info "Phase 5/13: Deploying nginx Ingress Controller..."
    deploy_nginx_ingress

    print_info "Phase 6/13: Deploying VictoriaMetrics..."
    deploy_victoriametrics

    print_info "Phase 7/13: Deploying Prometheus and Grafana..."
    deploy_prometheus

    print_info "Phase 8/13: Deploying Loki..."
    deploy_loki

    print_info "Phase 9/13: Deploying Tempo..."
    deploy_tempo

    print_info "Phase 10/13: Deploying Ingress Routes..."
    deploy_ingress

    print_info "Phase 11/13: Registering Locust metrics..."
    apply_locust_servicemonitor

    print_info "Phase 12/13: Deploying Locust Dashboards..."
    deploy_locust_dashboards

    print_info "Phase 13/13: Saving Configuration..."
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
    print_step "2. Port-forward Grafana: kubectl port-forward -n $GRAFANA_NAMESPACE svc/$PROM_HELM_RELEASE 3000:80"
    print_step "3. Access Grafana at http://localhost:3000"
    print_step "4. Login with admin / $GRAFANA_ADMIN_PASSWORD"
    print_step "5. Grafana already includes Prometheus, VictoriaMetrics, Loki, and Tempo datasources"
    print_step "6. Import or customize dashboards as needed"
    print_step "7. Monitor metrics, logs, and traces in real-time"
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
    print_info "  kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/$PROM_SERVICE_NAME 9090:9090"
    print_info "  Then visit: http://localhost:9090/targets"
    echo ""

    print_section "Cleanup"
    print_warning "To remove observability stack, run:"
    echo ""
    print_status "  helm uninstall $PROM_HELM_RELEASE -n $PROMETHEUS_NAMESPACE"
    print_status "  helm uninstall $VICTORIA_HELM_RELEASE -n $PROMETHEUS_NAMESPACE"
    print_status "  helm uninstall $LOKI_HELM_RELEASE -n $PROMETHEUS_NAMESPACE"
    print_status "  helm uninstall $TEMPO_HELM_RELEASE -n $PROMETHEUS_NAMESPACE"
    print_status "  kubectl delete namespace $PROMETHEUS_NAMESPACE"
    echo ""

    print_success "Observability setup completed successfully!"
}

# Execute main function
main
