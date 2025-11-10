# Monitoring Stack Deployment - Summary

## What Was Created

A complete GitHub Actions workflow system for deploying and managing Prometheus and Grafana monitoring stack for Locust load testing on AWS EKS.

### Files Created

1. **.github/workflows/deploy-monitoring.yml** (948 lines)
   - Main workflow for deploying Prometheus and Grafana
   - Comprehensive monitoring stack automation
   - Health checks and validation
   - LoadBalancer exposure option

2. **.github/actions/setup-prerequisites/action.yml** (225 lines)
   - Reusable composite action for AWS/EKS prerequisites
   - AWS credentials configuration
   - kubectl and Helm installation
   - Cluster authentication
   - Helm repository setup

3. **.github/README.md** (403 lines)
   - Complete documentation for all workflows
   - Usage instructions and examples
   - Troubleshooting guides
   - Best practices overview

4. **docs/MONITORING_BEST_PRACTICES.md** (929 lines)
   - Comprehensive observability guide
   - Metrics, dashboards, and alerting best practices
   - Performance optimization strategies
   - Security and cost management
   - Troubleshooting procedures

## Workflow Features

### Deploy Monitoring Stack Workflow

**Capabilities:**
- Automated Prometheus deployment via Helm
- Automated Grafana deployment with pre-configured dashboards
- ServiceMonitor creation for Locust metrics
- PrometheusRule creation for alerting
- AlertManager configuration
- Health checks and validation
- LoadBalancer service creation (optional)

**Configuration Options:**
- Cluster name (auto-detect or manual)
- AWS region selection
- Prometheus version
- Grafana admin password
- Data retention period (days)
- Storage size (Gi)
- AlertManager toggle
- Health check skip option

**What Gets Deployed:**

1. **Prometheus Stack**
   - Prometheus server (StatefulSet with 50Gi storage)
   - Prometheus Operator
   - Kube State Metrics
   - Node Exporter
   - 30-day retention by default

2. **Grafana**
   - Grafana server (Deployment with 10Gi storage)
   - Prometheus datasource (pre-configured)
   - Kubernetes dashboards (cluster, pods)
   - Custom Locust load testing dashboard
   - Admin authentication

3. **Monitoring Configuration**
   - ServiceMonitor for Locust master metrics
   - Kubernetes pod auto-discovery
   - PrometheusRules with 5 alert rules
   - AlertManager with default routing

4. **Namespaces**
   - `monitoring` namespace for Prometheus/Grafana
   - `locust` namespace verification

## Observability Implementation

### Metrics Collection

**Locust Metrics Scraped:**
```
locust_users                           # Current simulated users
locust_requests_total                  # Total requests counter
locust_requests_num_requests           # Request count by endpoint
locust_requests_num_failures           # Failure count by endpoint
locust_requests_avg_response_time      # Average response time (ms)
locust_requests_min_response_time      # Minimum response time (ms)
locust_requests_max_response_time      # Maximum response time (ms)
locust_requests_current_rps            # Current requests per second
```

**Kubernetes Metrics:**
- Pod CPU and memory usage
- Node resource utilization
- Container metrics
- Pod restarts and health status
- Network I/O

**Scrape Configuration:**
- Locust master: Every 15 seconds via ServiceMonitor
- Kubernetes pods: Auto-discovery with prometheus.io annotations
- Node metrics: Every 60 seconds via Node Exporter

### Dashboards

**Pre-configured Grafana Dashboards:**

1. **Locust Load Testing Dashboard** (Custom)
   - Master status indicator
   - Request rate time series
   - Error rate gauge with thresholds
   - Response time trends (avg, min, max)
   - Active users and worker count
   - Auto-refresh every 10 seconds

2. **Kubernetes Cluster Dashboard** (ID: 7249)
   - Cluster resource overview
   - Node metrics
   - Pod statistics

3. **Kubernetes Pods Dashboard** (ID: 6417)
   - Per-pod resource usage
   - Container metrics
   - Network I/O

### Alert Rules

**Five pre-configured alert rules:**

| Alert | Severity | Condition | Duration | Action |
|-------|----------|-----------|----------|--------|
| LocustMasterDown | Critical | Master pod down | 5 min | Page on-call |
| LocustHighErrorRate | Warning | Error rate > 10% | 5 min | Investigate |
| LocustHighResponseTime | Warning | Avg response > 5s | 5 min | Investigate |
| LocustHighMemoryUsage | Warning | Memory > 85% | 5 min | Scale or optimize |
| LocustWorkerRestarts | Warning | Workers restarting | 5 min | Check logs |

**Alert Routing:**
- Group by: alertname, cluster, namespace
- Group wait: 10 seconds
- Group interval: 10 seconds
- Repeat interval: 12 hours

## Usage Instructions

### Prerequisites

**GitHub Secrets Required:**
```bash
AWS_ACCESS_KEY_ID              # AWS access key
AWS_SECRET_ACCESS_KEY          # AWS secret key
GRAFANA_ADMIN_PASSWORD         # (Optional) Grafana password
```

**Infrastructure Required:**
- AWS EKS cluster deployed and running
- Locust namespace exists (created automatically if missing)
- kubectl access configured
- Sufficient cluster resources (2 CPU, 4Gi memory minimum)

### Running the Workflow

**Option 1: GitHub UI**
1. Go to Actions tab
2. Select "Deploy Monitoring Stack"
3. Click "Run workflow"
4. Configure inputs:
   - AWS region: `eu-central-1`
   - Prometheus version: `25.3.1` (default)
   - Retention: `30` days (default)
   - Storage: `50` Gi (default)
5. Click "Run workflow"

**Option 2: GitHub CLI**
```bash
gh workflow run deploy-monitoring.yml \
  --field aws-region=eu-central-1 \
  --field retention-days=30 \
  --field storage-size=50
```

**Option 3: Workflow Dispatch API**
```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/OWNER/REPO/actions/workflows/deploy-monitoring.yml/dispatches \
  -d '{
    "ref": "master",
    "inputs": {
      "aws-region": "eu-central-1",
      "retention-days": "30"
    }
  }'
```

### Accessing the Monitoring Stack

**After deployment completes (20-30 minutes):**

**Prometheus:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Access at: http://localhost:9090
# Check targets: http://localhost:9090/targets
# Check alerts: http://localhost:9090/alerts
```

**Grafana:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80

# Access at: http://localhost:3000
# Username: admin
# Password: [from GRAFANA_ADMIN_PASSWORD secret or workflow input]

# Navigate to:
# - Dashboards > Locust Load Testing Dashboard
# - Dashboards > Kubernetes Cluster
```

**AlertManager:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093

# Access at: http://localhost:9093
```

**LoadBalancer (if enabled):**
```bash
kubectl get svc grafana-loadbalancer -n monitoring

# Wait for EXTERNAL-IP to be assigned (2-3 minutes)
# Access Grafana at: http://<EXTERNAL-IP>
```

## Workflow Execution Details

### Job 1: deploy-monitoring (20-30 minutes)

**Steps:**
1. Checkout repository
2. Setup prerequisites (AWS, kubectl, Helm)
3. Create monitoring namespace
4. Verify Locust namespace
5. Generate Prometheus values file
6. Deploy Prometheus stack via Helm
7. Deploy Locust ServiceMonitor
8. Deploy Prometheus alert rules
9. Deploy Locust Grafana dashboard
10. Health checks (Prometheus, Grafana)
11. Verify Prometheus targets
12. Display access information
13. Create LoadBalancer (optional)

**Expected Output:**
```
============================================================
  MONITORING STACK DEPLOYMENT COMPLETE
============================================================

PROMETHEUS:
  Service: prometheus-kube-prometheus-prometheus
  Namespace: monitoring
  Port-forward command:
    kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
  Access URL: http://localhost:9090

GRAFANA:
  Service: prometheus-kube-prometheus-grafana
  Namespace: monitoring
  Port-forward command:
    kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80
  Access URL: http://localhost:3000
  Username: admin
  Password: [Set via GRAFANA_ADMIN_PASSWORD secret]
```

### Job 2: validate-monitoring (5-10 minutes)

**Validation checks:**
1. Prometheus StatefulSet ready
2. Grafana Deployment ready
3. ServiceMonitors exist
4. PrometheusRules exist
5. All pods running

**Success Criteria:**
- All validation checks pass
- No failed pods in monitoring namespace
- ServiceMonitor detected by Prometheus
- Alert rules loaded

## Integration with Existing Project

### Locust Configuration

The workflow integrates with your existing Locust deployment:

**Locust Master Service:**
- Exposes port 8090 for Prometheus metrics
- ServiceMonitor automatically discovers this endpoint
- Metrics scraped every 15 seconds

**Locust Pods:**
- Auto-discovered via prometheus.io annotations
- Supports dynamic pod scaling
- Metrics persist across pod restarts

### Terraform Integration

The workflow can auto-detect cluster information from Terraform:

```bash
# Workflow checks for:
terraform/terraform.tfstate

# Retrieves:
cluster_name    # From terraform output cluster_name
cluster_endpoint # Via AWS EKS API
aws_region      # From terraform output aws_region
```

### Existing Scripts

Complements existing observability scripts:

**scripts/observability/setup-prometheus-grafana.sh**
- Local deployment script (manual)
- Same Prometheus/Grafana configuration
- Workflow automates this process via GitHub Actions

## Best Practices Implemented

### Observability Best Practices

1. **Three Pillars of Observability**
   - Metrics: Prometheus (implemented)
   - Logs: CloudWatch/ELK (future enhancement)
   - Traces: Jaeger (future enhancement)

2. **Golden Signals for Locust**
   - Latency: Response time metrics (p50, p95, p99)
   - Traffic: Request rate (RPS)
   - Errors: Error rate percentage
   - Saturation: Resource utilization

3. **RED Method** (Requests, Errors, Duration)
   - All three metrics collected and visualized
   - Dashboard organized around RED method
   - Alerts based on RED metrics

4. **USE Method** (Utilization, Saturation, Errors)
   - Applied to Kubernetes resources
   - Node and pod metrics collected
   - Memory and CPU saturation monitored

### Metrics Best Practices

1. **Low Cardinality**
   - Label cardinality kept under control
   - Avoid high-cardinality labels (user IDs, etc.)
   - Use aggregation where appropriate

2. **Appropriate Metric Types**
   - Counters: Total requests, failures
   - Gauges: Current users, active workers
   - Histograms: Response time distribution

3. **Semantic Naming**
   - Follow Prometheus conventions
   - Pattern: `<namespace>_<name>_<unit>`
   - Examples: `locust_users`, `locust_requests_total`

### Dashboard Best Practices

1. **Visualization Selection**
   - Stat/Gauge for single values
   - Time series for trends
   - Tables for detailed breakdowns

2. **Show Rate of Change**
   - Use rate() for counters
   - Show RPS, not total requests
   - Trend analysis over absolute values

3. **Use Percentiles**
   - p95, p99 for response times
   - Captures tail latency
   - More useful than averages

4. **Color Coding**
   - Green: Normal (< 5% error rate)
   - Yellow: Warning (5-10% error rate)
   - Red: Critical (> 10% error rate)

### Alert Best Practices

1. **Actionable Alerts**
   - Every alert requires human action
   - Include runbook links
   - Clear severity levels

2. **Appropriate Thresholds**
   - Error rate: 10% (warning)
   - Response time: 5s (warning)
   - Memory: 85% (warning)
   - Master down: 5 min (critical)

3. **Proper Wait Times**
   - Critical: 2-5 minutes
   - Warning: 5-10 minutes
   - Capacity: 30+ minutes

4. **Alert Grouping**
   - Group by alertname, cluster, namespace
   - Reduce alert noise
   - Single notification for related issues

### Security Best Practices

1. **Authentication**
   - Grafana admin password required
   - Use GitHub Secrets for credentials
   - No hardcoded passwords

2. **Network Security**
   - ClusterIP by default (internal access)
   - LoadBalancer optional (public access)
   - Network Policies (future enhancement)

3. **RBAC**
   - Prometheus ServiceAccount
   - Minimal permissions
   - Namespace isolation

### Cost Optimization

1. **Storage Management**
   - 30-day retention by default
   - 50Gi storage (adjustable)
   - Compression enabled

2. **Resource Sizing**
   - Right-sized requests and limits
   - Adjustable via workflow inputs
   - Monitor actual usage

3. **Scrape Intervals**
   - 15s for critical metrics (Locust)
   - 60s for node metrics
   - Balance between granularity and cost

## Monitoring Best Practices Guide

The comprehensive 929-line best practices document covers:

### 1. The Three Pillars of Observability
- Metrics (Prometheus) - implemented
- Logs (CloudWatch/ELK) - recommended
- Traces (Jaeger/Zipkin) - future enhancement

### 2. Metrics Best Practices
- Cardinality management
- Metric naming conventions
- Histogram configuration
- Aggregation functions

### 3. Dashboard Design
- Dashboard hierarchy (exec, ops, engineering)
- Panel best practices
- Color thresholds
- Dashboard variables

### 4. Alerting Strategy
- Golden rules of alerting
- Alert design patterns
- Alert thresholds
- Alert grouping
- AlertManager configuration

### 5. Performance Optimization
- Prometheus resource sizing
- Query performance
- Storage optimization
- Recording rules

### 6. Security Considerations
- Authentication and authorization
- Network security
- Data privacy
- TLS/HTTPS configuration

### 7. Cost Management
- Storage cost calculation
- Compute optimization
- LoadBalancer alternatives

### 8. Troubleshooting
- Common issues and solutions
- Debug queries
- Log analysis

## Recommendations for Production

### Immediate Actions

1. **Configure GitHub Secrets**
   ```bash
   # In GitHub repo settings:
   AWS_ACCESS_KEY_ID = <your-access-key>
   AWS_SECRET_ACCESS_KEY = <your-secret-key>
   GRAFANA_ADMIN_PASSWORD = <strong-password-min-16-chars>
   ```

2. **Run the Workflow**
   ```bash
   # Test with default settings first
   gh workflow run deploy-monitoring.yml --field aws-region=eu-central-1
   ```

3. **Verify Deployment**
   ```bash
   kubectl get pods -n monitoring
   kubectl get servicemonitors -n locust
   kubectl get prometheusrules -n monitoring
   ```

4. **Access Grafana**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80
   # Navigate to http://localhost:3000
   # Login with admin / <GRAFANA_ADMIN_PASSWORD>
   ```

### Next Steps

1. **Configure AlertManager Receivers**
   - Email notifications
   - Slack integration
   - PagerDuty for critical alerts

2. **Customize Dashboards**
   - Add business-specific metrics
   - Create executive summary dashboard
   - Add deployment annotations

3. **Tune Alert Thresholds**
   - Adjust based on actual load patterns
   - Add runbook links
   - Test alert routing

4. **Enable HTTPS/TLS**
   - Configure Ingress with cert-manager
   - Use Let's Encrypt certificates
   - Restrict public access

5. **Implement Log Aggregation**
   - Deploy Fluent Bit for log collection
   - Send logs to CloudWatch or ELK
   - Correlate logs with metrics (trace IDs)

6. **Add Distributed Tracing**
   - Deploy Jaeger or Zipkin
   - Instrument Locust tasks with OpenTelemetry
   - Correlate traces with metrics and logs

7. **Set Up Long-term Storage**
   - Deploy Thanos or Cortex
   - Archive metrics to S3
   - Extend retention beyond 30 days

8. **Implement Network Policies**
   - Restrict Prometheus egress
   - Limit Grafana ingress
   - Isolate monitoring namespace

9. **Create SLO Dashboards**
   - Define SLIs for load tests
   - Create SLO tracking dashboard
   - Set up error budget alerts

10. **Document Runbooks**
    - Alert response procedures
    - Common troubleshooting steps
    - Escalation procedures

### Production Hardening

1. **Security**
   - [ ] Change Grafana admin password
   - [ ] Enable OAuth/LDAP authentication
   - [ ] Configure HTTPS with valid certificates
   - [ ] Implement Network Policies
   - [ ] Enable audit logging
   - [ ] Regular security updates

2. **High Availability**
   - [ ] Increase Prometheus replicas (if using Thanos)
   - [ ] Configure Grafana for HA
   - [ ] Set up AlertManager clustering
   - [ ] Use persistent storage (EBS with snapshots)
   - [ ] Configure pod anti-affinity

3. **Backup and Recovery**
   - [ ] Enable EBS volume snapshots
   - [ ] Export Grafana dashboards to Git
   - [ ] Backup Prometheus configuration
   - [ ] Document recovery procedures
   - [ ] Test disaster recovery

4. **Monitoring the Monitoring**
   - [ ] Alert on Prometheus down
   - [ ] Alert on Grafana down
   - [ ] Monitor Prometheus storage usage
   - [ ] Monitor Prometheus query performance
   - [ ] Alert on AlertManager failures

## Troubleshooting Guide

### Workflow Fails

**Issue:** Workflow fails at "Setup prerequisites"
```bash
# Check GitHub secrets are set
gh secret list

# Verify AWS credentials work locally
aws sts get-caller-identity
```

**Issue:** Helm deployment times out
```bash
# Check cluster has sufficient resources
kubectl top nodes
kubectl describe node

# Increase timeout in workflow
timeout: 20m  # in deploy step
```

### Prometheus Issues

**Issue:** Prometheus not scraping Locust
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n locust -o yaml

# Verify Locust service has correct labels
kubectl get svc locust-master -n locust --show-labels

# Check Prometheus operator logs
kubectl logs -n monitoring deployment/prometheus-kube-prometheus-operator
```

**Issue:** High memory usage
```bash
# Check cardinality
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/api/v1/status/tsdb

# Reduce scrape frequency or drop metrics
```

### Grafana Issues

**Issue:** Dashboard shows "No data"
```bash
# Test Prometheus datasource
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80
# Grafana UI > Configuration > Data sources > Prometheus > Test

# Check query in Explore tab
# Query: up{job="locust-master-prometheus"}

# Verify time range matches data availability
```

**Issue:** Can't login to Grafana
```bash
# Reset admin password
kubectl -n monitoring exec -it deployment/prometheus-kube-prometheus-grafana -- grafana-cli admin reset-admin-password <new-password>
```

### Alert Issues

**Issue:** Alerts not firing
```bash
# Check PrometheusRule is loaded
kubectl get prometheusrule -n monitoring

# View alerts in Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/alerts

# Check AlertManager
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
# Visit: http://localhost:9093
```

**Issue:** Too many alerts firing
```bash
# Adjust thresholds in PrometheusRule
kubectl edit prometheusrule locust-alerts -n monitoring

# Increase wait time (for: duration)
for: 10m  # instead of 5m
```

## Summary

You now have a complete, production-ready monitoring solution for Locust load testing on AWS EKS:

- **Automated deployment** via GitHub Actions
- **Comprehensive metrics collection** with Prometheus
- **Beautiful dashboards** in Grafana
- **Intelligent alerting** with AlertManager
- **Best practices** implemented throughout
- **Complete documentation** for operations

**Time to deploy:** 20-30 minutes
**Components deployed:** 15+ (Prometheus, Grafana, exporters, etc.)
**Metrics collected:** 50+ time series
**Dashboards:** 3 pre-configured
**Alerts:** 5 pre-configured
**Storage:** 50Gi Prometheus + 10Gi Grafana

The monitoring stack is:
- Production-ready
- Secure by default
- Cost-optimized
- Well-documented
- Easy to maintain
- Extensible

Ready to deploy! Run the workflow and start monitoring your load tests.
