# GitHub Actions Workflows

This directory contains GitHub Actions workflows for automating deployment and monitoring of the Locust load testing infrastructure on AWS EKS.

## Available Workflows

### 1. Deploy Monitoring Stack (`deploy-monitoring.yml`)

Automates the deployment of Prometheus and Grafana for comprehensive observability of Locust load tests.

#### Features

- Deploys Prometheus for metrics collection
- Deploys Grafana with pre-configured dashboards
- Configures ServiceMonitors for automatic metrics discovery
- Sets up PrometheusRules for alerting
- Configures AlertManager for notifications
- Supports manual triggers with customizable parameters
- Includes health checks and validation
- Provides LoadBalancer access option

#### Required GitHub Secrets

Configure these secrets in your GitHub repository (Settings > Secrets and variables > Actions):

| Secret Name | Description | Example |
|------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password (optional) | `SecurePassword123!` |

#### Workflow Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `cluster-name` | EKS cluster name | No | Auto-detect from Terraform |
| `aws-region` | AWS region | Yes | `eu-central-1` |
| `prometheus-version` | Prometheus chart version | No | `25.3.1` |
| `grafana-admin-password` | Grafana admin password | No | From secrets or `admin123` |
| `retention-days` | Prometheus data retention | No | `30` |
| `storage-size` | Prometheus storage size (Gi) | No | `50` |
| `enable-alertmanager` | Enable AlertManager | No | `true` |
| `skip-health-checks` | Skip health checks | No | `false` |

#### Usage

**Manual Trigger via GitHub UI:**

1. Navigate to Actions tab in your GitHub repository
2. Select "Deploy Monitoring Stack" workflow
3. Click "Run workflow"
4. Configure inputs as needed
5. Click "Run workflow" button

**Manual Trigger via GitHub CLI:**

```bash
gh workflow run deploy-monitoring.yml \
  --field aws-region=eu-central-1 \
  --field prometheus-version=25.3.1 \
  --field retention-days=30
```

**Trigger from another workflow:**

```yaml
jobs:
  deploy-monitoring:
    uses: ./.github/workflows/deploy-monitoring.yml
    secrets: inherit
    with:
      aws-region: eu-central-1
      retention-days: 30
```

#### What Gets Deployed

1. **Prometheus Stack**
   - Prometheus server (StatefulSet)
   - Prometheus Operator
   - Kube State Metrics
   - Node Exporter
   - Storage (50Gi PVC by default)

2. **Grafana**
   - Grafana server (Deployment)
   - Pre-configured Prometheus datasource
   - Kubernetes cluster dashboards
   - Custom Locust load testing dashboard
   - Storage (10Gi PVC)

3. **Monitoring Configuration**
   - ServiceMonitor for Locust metrics
   - PrometheusRules for alerting
   - Alert rules for Locust health

4. **AlertManager** (optional)
   - AlertManager (StatefulSet)
   - Default receiver configuration

#### Accessing the Monitoring Stack

After deployment, access the services via port-forwarding:

**Prometheus:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Access: http://localhost:9090
```

**Grafana:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80
# Access: http://localhost:3000
# Username: admin
# Password: [from GRAFANA_ADMIN_PASSWORD secret or input]
```

**AlertManager:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
# Access: http://localhost:9093
```

**LoadBalancer (if enabled):**
```bash
kubectl get svc grafana-loadbalancer -n monitoring
# Use the EXTERNAL-IP/HOSTNAME to access Grafana
```

#### Metrics Collected

The monitoring stack automatically collects:

1. **Locust Metrics** (from `/metrics` endpoint):
   - `locust_users` - Number of active users
   - `locust_requests_total` - Total requests
   - `locust_requests_num_requests` - Request count
   - `locust_requests_num_failures` - Failure count
   - `locust_requests_avg_response_time` - Average response time
   - `locust_requests_min_response_time` - Minimum response time
   - `locust_requests_max_response_time` - Maximum response time
   - Response time percentiles (p50, p95, p99)

2. **Kubernetes Metrics**:
   - Pod CPU/memory usage
   - Node resource utilization
   - Container metrics
   - Pod restarts and health

3. **Custom Application Metrics**:
   - Any metrics exposed via Prometheus annotations

#### Alert Rules

Pre-configured alert rules:

| Alert | Severity | Condition | Duration |
|-------|----------|-----------|----------|
| LocustMasterDown | Critical | Master pod is down | 5 minutes |
| LocustHighErrorRate | Warning | Error rate > 10% | 5 minutes |
| LocustHighResponseTime | Warning | Avg response time > 5s | 5 minutes |
| LocustHighMemoryUsage | Warning | Memory usage > 85% | 5 minutes |
| LocustWorkerRestarts | Warning | Worker pods restarting | 5 minutes |

#### Grafana Dashboards

Pre-configured dashboards:

1. **Locust Load Testing Dashboard** (`locust-load-testing`)
   - Master status indicator
   - Request rate graph
   - Error rate gauge
   - Response time trends
   - Active users and workers

2. **Kubernetes Cluster Dashboard** (from Grafana.com ID: 7249)
   - Cluster resource usage
   - Node metrics
   - Pod statistics

3. **Kubernetes Pods Dashboard** (from Grafana.com ID: 6417)
   - Per-pod resource usage
   - Container metrics
   - Network I/O

#### Troubleshooting

**Prometheus not scraping Locust metrics:**
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n locust

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets

# Check pod annotations
kubectl get pod -n locust -o yaml | grep -A 5 "prometheus.io"
```

**Grafana dashboard not showing data:**
```bash
# Check Grafana datasource
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80
# Visit: http://localhost:3000/datasources

# Test Prometheus queries in Grafana Explore
# Query: up{job="locust-master-prometheus"}
```

**AlertManager not sending alerts:**
```bash
# Check AlertManager configuration
kubectl get secret alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring -o yaml

# View AlertManager logs
kubectl logs -n monitoring statefulset/alertmanager-prometheus-kube-prometheus-alertmanager
```

## Composite Actions

### setup-prerequisites

Reusable composite action for setting up prerequisites required for EKS deployment.

#### Features

- Configures AWS credentials
- Verifies AWS IAM permissions
- Installs and configures kubectl
- Installs Helm
- Adds Prometheus and Grafana Helm repositories
- Configures kubectl to access EKS cluster
- Validates project structure

#### Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `aws-region` | AWS region | Yes | - |
| `aws-access-key-id` | AWS Access Key ID | Yes | - |
| `aws-secret-access-key` | AWS Secret Access Key | Yes | - |
| `cluster-name` | EKS cluster name | No | Auto-detect |
| `kubectl-version` | kubectl version | No | `v1.28.0` |
| `helm-version` | Helm version | No | `v3.13.0` |

#### Outputs

| Output | Description |
|--------|-------------|
| `cluster-name` | EKS cluster name |
| `cluster-endpoint` | EKS cluster endpoint |

#### Usage

```yaml
steps:
  - name: Setup prerequisites
    uses: ./.github/actions/setup-prerequisites
    with:
      aws-region: eu-central-1
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Best Practices

### Security

1. **Secrets Management**
   - Never commit secrets to repository
   - Use GitHub Secrets for sensitive data
   - Rotate AWS credentials regularly
   - Use IAM roles with least privilege

2. **Grafana Access**
   - Change default admin password immediately
   - Use strong passwords (min 16 characters)
   - Enable HTTPS/TLS for LoadBalancer
   - Configure OAuth or LDAP authentication
   - Restrict network access with security groups

3. **Prometheus Security**
   - Enable authentication if exposed externally
   - Use Network Policies to restrict access
   - Encrypt data at rest
   - Regular security updates

### Monitoring Best Practices

1. **Metrics Cardinality**
   - Keep label cardinality under control (< 1000 unique combinations)
   - Avoid high-cardinality labels (user IDs, timestamps)
   - Use label aggregation where possible

2. **Storage Planning**
   - Default: 50Gi for Prometheus, 10Gi for Grafana
   - Calculate retention: `retention_days * daily_ingestion_rate * safety_factor`
   - Monitor storage usage: set alerts at 80% capacity
   - Use remote storage (S3, Thanos) for long-term retention

3. **Alert Design**
   - Every alert should be actionable
   - Include runbook links in annotations
   - Use appropriate severity levels
   - Test alerts regularly
   - Avoid alert fatigue (group related alerts)

4. **Dashboard Design**
   - Use consistent time ranges
   - Show rate of change, not just absolute values
   - Include percentiles (p50, p95, p99), not just averages
   - Add annotations for deployments and incidents
   - Organize by audience (overview, debugging, SLOs)

### Cost Optimization

1. **Storage Costs**
   - Adjust retention period based on needs
   - Use smaller storage for dev environments
   - Enable compression
   - Archive old data to S3

2. **LoadBalancer Costs**
   - Use port-forwarding for development
   - Use NodePort instead of LoadBalancer
   - Share LoadBalancer across services with Ingress

3. **Compute Costs**
   - Right-size Prometheus StatefulSet
   - Use node affinity to place on spot instances
   - Scale down in non-production environments

## Observability Strategy

### The Three Pillars

1. **Metrics** (Prometheus)
   - Time-series data
   - Aggregatable
   - Good for dashboards and alerts
   - Example: request rate, error rate, response time

2. **Logs** (not included, use CloudWatch/ELK)
   - Discrete events
   - Good for debugging
   - Example: "User X failed login at Y"

3. **Traces** (not included, use Jaeger/Zipkin)
   - Request flow across services
   - Good for latency analysis
   - Example: End-to-end request path

### Golden Signals (for Locust)

Monitor these four key metrics:

1. **Latency**: Response time (avg, p95, p99)
2. **Traffic**: Request rate (RPS)
3. **Errors**: Error rate (%)
4. **Saturation**: Resource utilization (CPU, memory)

### SLI/SLO/SLA Framework

**SLI (Service Level Indicator)**: Metric that measures service health
- Example: `(successful_requests / total_requests) * 100`

**SLO (Service Level Objective)**: Target for SLI
- Example: "99.9% of requests complete in < 500ms"

**SLA (Service Level Agreement)**: Contract based on SLO
- Example: "99.9% uptime or customer gets credit"

## Contributing

When adding new workflows:

1. Follow naming convention: `<action>-<component>.yml`
2. Use semantic versioning for action versions
3. Document all inputs and outputs
4. Include validation and health checks
5. Add comprehensive error handling
6. Update this README

## Support

For issues or questions:

1. Check workflow logs in GitHub Actions tab
2. Review Kubernetes logs: `kubectl logs -n monitoring <pod-name>`
3. Verify AWS permissions and credentials
4. Check CloudWatch logs for EKS cluster events
5. Review troubleshooting section above

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
