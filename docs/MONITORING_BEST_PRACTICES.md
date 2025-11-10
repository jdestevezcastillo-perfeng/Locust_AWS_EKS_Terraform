# Monitoring Best Practices for Locust on AWS EKS

This guide provides comprehensive best practices for implementing observability in your Locust load testing infrastructure.

## Table of Contents

- [Overview](#overview)
- [The Three Pillars of Observability](#the-three-pillars-of-observability)
- [Metrics Best Practices](#metrics-best-practices)
- [Dashboard Design](#dashboard-design)
- [Alerting Strategy](#alerting-strategy)
- [Performance Optimization](#performance-optimization)
- [Security Considerations](#security-considerations)
- [Cost Management](#cost-management)
- [Troubleshooting](#troubleshooting)

## Overview

Effective observability is critical for understanding system behavior, diagnosing issues, and ensuring reliability. This guide focuses on Prometheus and Grafana deployment for Locust load testing on AWS EKS.

### Why Observability Matters

- **Faster MTTD** (Mean Time To Detect): Identify issues before users report them
- **Faster MTTR** (Mean Time To Resolve): Diagnose and fix issues quickly
- **Capacity Planning**: Understand resource needs and growth patterns
- **Performance Optimization**: Identify bottlenecks and inefficiencies
- **Business Insights**: Track load test metrics and trends

## The Three Pillars of Observability

### 1. Metrics (Prometheus)

**What**: Numerical measurements over time
**When**: Dashboards, alerts, capacity planning
**Retention**: Days to weeks (30 days default)

**Locust Metrics:**
```
locust_users                           # Current number of simulated users
locust_requests_total                  # Total requests counter
locust_requests_num_requests           # Request count by endpoint
locust_requests_num_failures           # Failure count by endpoint
locust_requests_avg_response_time      # Average response time (ms)
locust_requests_min_response_time      # Minimum response time (ms)
locust_requests_max_response_time      # Maximum response time (ms)
locust_requests_current_rps            # Current requests per second
```

**Best Practices:**
- Use counters for cumulative values (total requests)
- Use gauges for point-in-time values (current users)
- Use histograms for distribution data (response times)
- Keep label cardinality low (< 1000 unique combinations)
- Use consistent naming: `<namespace>_<name>_<unit>`

### 2. Logs (CloudWatch/ELK Stack)

**What**: Discrete events with context
**When**: Debugging, audit trails, security investigation
**Retention**: Weeks to months

**Implementation:**
```yaml
# Locust pod logs to CloudWatch
fluent-bit:
  enabled: true
  cloudWatch:
    enabled: true
    region: eu-central-1
    logGroupName: /aws/eks/locust-logs
```

**Best Practices:**
- Use structured logging (JSON format)
- Include correlation IDs (trace_id, request_id)
- Use appropriate log levels (ERROR, WARN, INFO, DEBUG)
- Avoid logging sensitive data (PII, credentials)
- Include context: timestamp, pod name, namespace

### 3. Traces (Jaeger/Zipkin - Future Enhancement)

**What**: Request flow across services
**When**: Latency analysis, dependency mapping
**Retention**: Hours to days

**Implementation:**
```python
# Add OpenTelemetry to Locust
from opentelemetry import trace
from opentelemetry.exporter.jaeger import JaegerExporter

tracer = trace.get_tracer(__name__)

@task
def my_task(self):
    with tracer.start_as_current_span("http_request"):
        self.client.get("/api/endpoint")
```

## Metrics Best Practices

### Cardinality Management

**Problem**: High cardinality causes performance issues and costs

**Bad Example (High Cardinality):**
```
# DON'T: User ID as label (millions of unique values)
locust_requests{user_id="12345", endpoint="/api/users"}
```

**Good Example (Low Cardinality):**
```
# DO: Aggregate by endpoint and method
locust_requests{endpoint="/api/users", method="GET"}
```

**Guidelines:**
- Total unique label combinations should be < 10,000
- Per-metric label combinations should be < 1,000
- Avoid labels for: user IDs, timestamps, random values
- Good labels: endpoint, method, status_code, environment

### Metric Naming Conventions

Follow Prometheus naming conventions:

```
# Pattern: <namespace>_<subsystem>_<name>_<unit>

locust_requests_total                  # Counter: total suffix
locust_users                           # Gauge: no suffix needed
locust_response_time_seconds           # Histogram: _seconds suffix
locust_response_time_seconds_bucket    # Histogram bucket
locust_response_time_seconds_sum       # Histogram sum
locust_response_time_seconds_count     # Histogram count
```

### Histogram Configuration

Configure appropriate buckets for response time histograms:

```yaml
# Good: Covers expected range with useful granularity
buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

# Bad: Too coarse, missing useful data
buckets: [1.0, 10.0, 100.0]

# Bad: Too fine, too many time series
buckets: [0.001, 0.002, 0.003, ..., 10.0]  # 100+ buckets
```

### Aggregation Functions

**Use rate() for counters:**
```promql
# Request rate (requests per second)
rate(locust_requests_total[5m])

# Error rate percentage
(rate(locust_requests_num_failures[5m]) / rate(locust_requests_total[5m])) * 100
```

**Use histogram_quantile() for percentiles:**
```promql
# 95th percentile response time
histogram_quantile(0.95, rate(locust_response_time_seconds_bucket[5m]))

# 99th percentile response time
histogram_quantile(0.99, rate(locust_response_time_seconds_bucket[5m]))
```

**Use avg_over_time() for gauges:**
```promql
# Average active users over 5 minutes
avg_over_time(locust_users[5m])
```

## Dashboard Design

### Dashboard Hierarchy

Create dashboards for different audiences:

1. **Executive Dashboard** (Business View)
   - Test summary metrics
   - Success/failure rates
   - Key SLI indicators
   - Test duration and status

2. **Service Health Dashboard** (Operations View)
   - Golden signals (latency, traffic, errors, saturation)
   - Request rates and error rates
   - Response time percentiles
   - Active users and workers

3. **Debugging Dashboard** (Engineering View)
   - Per-endpoint metrics
   - Resource utilization
   - Container metrics
   - Network I/O

### Panel Best Practices

**1. Use Appropriate Visualizations:**

- **Stat/Gauge**: Single value (error rate %, current users)
- **Time Series**: Trends over time (RPS, response time)
- **Bar Chart**: Comparison (errors by endpoint)
- **Heatmap**: Distribution over time (response time distribution)
- **Table**: Detailed breakdown (per-endpoint statistics)

**2. Show Rate of Change:**
```promql
# Good: Show rate, not absolute counter
rate(locust_requests_total[5m])

# Bad: Counter values are not useful for visualization
locust_requests_total
```

**3. Use Percentiles, Not Averages:**
```promql
# Good: 95th percentile (captures tail latency)
histogram_quantile(0.95, rate(locust_response_time_seconds_bucket[5m]))

# Less useful: Average (hides outliers)
avg(locust_response_time_seconds)
```

**4. Add Context with Annotations:**
```json
{
  "annotations": {
    "list": [
      {
        "datasource": "Prometheus",
        "enable": true,
        "expr": "changes(locust_users[1m]) != 0",
        "iconColor": "blue",
        "name": "Load Changes",
        "tagKeys": "load_test"
      }
    ]
  }
}
```

### Color Thresholds

Use color to indicate health:

```json
{
  "thresholds": {
    "mode": "absolute",
    "steps": [
      {"color": "green", "value": null},      // 0-5%
      {"color": "yellow", "value": 5},        // 5-10%
      {"color": "red", "value": 10}           // >10%
    ]
  }
}
```

**Guidelines:**
- Green: Normal/healthy state
- Yellow: Warning/degraded state
- Red: Critical/failed state
- Use colorblind-friendly palettes

### Dashboard Variables

Use template variables for flexibility:

```json
{
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "query": "label_values(locust_users, namespace)",
        "current": {"value": "locust"}
      },
      {
        "name": "endpoint",
        "type": "query",
        "query": "label_values(locust_requests_total{namespace=\"$namespace\"}, name)",
        "multi": true,
        "includeAll": true
      }
    ]
  }
}
```

**Common Variables:**
- Namespace (environment isolation)
- Time range (last 1h, 24h, 7d)
- Endpoint (filter by API endpoint)
- Percentile (p50, p95, p99)

## Alerting Strategy

### The Golden Rules of Alerting

1. **Every alert must be actionable**
   - If no action is needed, don't alert
   - Alert should lead to investigation or mitigation

2. **Alerts should have runbooks**
   - Document what to do when alert fires
   - Include troubleshooting steps
   - Link to relevant dashboards

3. **Use appropriate severity levels**
   - Critical: Immediate action required (page on-call)
   - Warning: Action needed soon (ticket/email)
   - Info: For awareness only (dashboard/log)

4. **Avoid alert fatigue**
   - Group related alerts
   - Use sensible thresholds
   - Implement proper wait times

### Alert Design Patterns

**1. Symptom-Based Alerts (Good):**
```yaml
# Alert on user-visible symptoms
- alert: HighErrorRate
  expr: |
    (sum(rate(locust_requests_num_failures[5m])) /
     sum(rate(locust_requests_total[5m]))) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High error rate detected"
    description: "Error rate is {{ $value | humanizePercentage }}"
```

**2. Cause-Based Alerts (Less Useful):**
```yaml
# Alert on internal metrics (may not affect users)
- alert: HighCPU
  expr: container_cpu_usage > 80
  # This may not impact users, and may cause alert fatigue
```

### Alert Thresholds

**Use percentages for error rates:**
```promql
# Error rate > 5%
(rate(locust_requests_num_failures[5m]) / rate(locust_requests_total[5m])) > 0.05
```

**Use absolute values for critical resources:**
```promql
# Memory usage > 90%
(container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
```

**Use rate of change for anomaly detection:**
```promql
# Response time increased by 50% in last 10 minutes
(locust_response_time_seconds - locust_response_time_seconds offset 10m) /
locust_response_time_seconds offset 10m > 0.5
```

### Alert Duration (for: clause)

Choose appropriate wait times:

```yaml
# Critical alerts: Short duration (1-5 minutes)
- alert: ServiceDown
  expr: up{job="locust-master"} == 0
  for: 2m  # Wait 2 minutes before alerting

# Warning alerts: Medium duration (5-15 minutes)
- alert: HighLatency
  expr: locust_response_time_seconds > 5
  for: 10m  # Wait 10 minutes before alerting

# Capacity alerts: Long duration (30-60 minutes)
- alert: StorageNearlFull
  expr: kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.15
  for: 30m  # Wait 30 minutes before alerting
```

### Alert Grouping

Group related alerts to reduce noise:

```yaml
route:
  group_by: ['alertname', 'cluster', 'namespace']
  group_wait: 10s           # Wait 10s before sending first alert
  group_interval: 10s       # Wait 10s before sending new alerts in group
  repeat_interval: 12h      # Resend alert every 12 hours if still firing
```

### Alert Annotations

Include helpful context:

```yaml
annotations:
  summary: "{{ $labels.alertname }} on {{ $labels.namespace }}"
  description: |
    Error rate is {{ $value | humanizePercentage }} (threshold: 5%)

    Affected endpoints: {{ $labels.endpoint }}

    Runbook: https://wiki.company.com/runbooks/high-error-rate
    Dashboard: https://grafana.company.com/d/locust-dashboard

    Investigation steps:
    1. Check Locust master logs: kubectl logs -n locust deployment/locust-master
    2. Review recent deployments or configuration changes
    3. Verify target service health
    4. Check network connectivity
```

### AlertManager Configuration

**Email Notifications:**
```yaml
receivers:
  - name: 'email-ops'
    email_configs:
      - to: 'ops-team@company.com'
        from: 'alertmanager@company.com'
        smarthost: 'smtp.company.com:587'
        auth_username: 'alertmanager'
        auth_password: '<secret>'
        headers:
          Subject: '{{ .GroupLabels.alertname }} - {{ .GroupLabels.namespace }}'
```

**Slack Notifications:**
```yaml
receivers:
  - name: 'slack-critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXX'
        channel: '#alerts-critical'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
```

**PagerDuty Integration:**
```yaml
receivers:
  - name: 'pagerduty-oncall'
    pagerduty_configs:
      - service_key: '<pagerduty-integration-key>'
        description: '{{ .GroupLabels.alertname }}'
```

## Performance Optimization

### Prometheus Resource Sizing

**Small deployment (dev):**
```yaml
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 1000m
    memory: 4Gi
storage: 20Gi
retention: 15d
```

**Medium deployment (staging):**
```yaml
resources:
  requests:
    cpu: 1000m
    memory: 4Gi
  limits:
    cpu: 2000m
    memory: 8Gi
storage: 50Gi
retention: 30d
```

**Large deployment (production):**
```yaml
resources:
  requests:
    cpu: 2000m
    memory: 8Gi
  limits:
    cpu: 4000m
    memory: 16Gi
storage: 200Gi
retention: 90d
```

### Query Performance

**1. Use recording rules for expensive queries:**
```yaml
groups:
  - name: locust_recording_rules
    interval: 30s
    rules:
      # Pre-calculate error rate
      - record: locust:error_rate:5m
        expr: |
          (sum(rate(locust_requests_num_failures[5m])) /
           sum(rate(locust_requests_total[5m])))

      # Pre-calculate 95th percentile response time
      - record: locust:response_time_seconds:p95
        expr: |
          histogram_quantile(0.95,
            sum(rate(locust_response_time_seconds_bucket[5m])) by (le, endpoint)
          )
```

**2. Use efficient time ranges:**
```promql
# Good: Specific time range
rate(locust_requests_total[5m])

# Bad: Unbounded time range
rate(locust_requests_total)
```

**3. Limit cardinality in queries:**
```promql
# Good: Aggregate before filtering
sum(rate(locust_requests_total[5m])) by (endpoint)

# Less efficient: Filter after aggregation
sum(rate(locust_requests_total{namespace="locust"}[5m])) by (endpoint)
```

### Storage Optimization

**1. Adjust scrape intervals:**
```yaml
# High-frequency for critical metrics
- job_name: 'locust-master'
  scrape_interval: 15s  # Default

# Lower frequency for less critical metrics
- job_name: 'node-exporter'
  scrape_interval: 60s  # Reduce storage by 4x
```

**2. Use metric relabeling to drop unnecessary metrics:**
```yaml
metric_relabel_configs:
  # Drop metrics we don't need
  - source_labels: [__name__]
    regex: 'go_.*'  # Drop Go runtime metrics
    action: drop

  # Keep only specific metrics
  - source_labels: [__name__]
    regex: 'locust_.*|up|kube_pod_status_phase'
    action: keep
```

**3. Enable compression:**
```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          # Use gp3 for better performance
          storageClassName: gp3
```

## Security Considerations

### Authentication and Authorization

**1. Enable Grafana Authentication:**
```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.company.com

    auth:
      disable_login_form: false

    auth.anonymous:
      enabled: false

    auth.basic:
      enabled: true

    # OAuth integration (recommended)
    auth.google:
      enabled: true
      client_id: <google-oauth-client-id>
      client_secret: <google-oauth-client-secret>
      allowed_domains: company.com
      allow_sign_up: true
```

**2. Restrict Prometheus Access:**
```yaml
prometheus:
  prometheusSpec:
    # Enable basic auth
    basicAuth:
      enabled: true
      username: admin
      password: <hashed-password>
```

**3. Use Kubernetes RBAC:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: prometheus-reader
  namespace: monitoring
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints"]
    verbs: ["get", "list", "watch"]
```

### Network Security

**1. Use Network Policies:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-network-policy
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: prometheus
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow from Grafana
    - from:
        - podSelector:
            matchLabels:
              app: grafana
      ports:
        - protocol: TCP
          port: 9090
  egress:
    # Allow scraping Locust
    - to:
        - namespaceSelector:
            matchLabels:
              name: locust
      ports:
        - protocol: TCP
          port: 8090
```

**2. Use TLS for external access:**
```yaml
grafana:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - grafana.company.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.company.com
```

### Data Privacy

**1. Scrub sensitive data:**
```yaml
metric_relabel_configs:
  # Remove sensitive labels
  - source_labels: [user_id, email, token]
    action: labeldrop
```

**2. Mask sensitive annotation values:**
```yaml
# In Grafana dashboard variables
"regex": "/^(.{4}).*(.{4})$/",  # Show only first/last 4 chars
```

## Cost Management

### Storage Costs

**Calculate storage needs:**
```
Storage = Samples/sec × Bytes/sample × Retention_seconds × Replication_factor

Example:
- 10,000 time series
- 1 sample every 15 seconds = 0.067 samples/sec
- 2 bytes per sample
- 30 days retention = 2,592,000 seconds
- Replication factor = 2

Storage = 10,000 × 0.067 × 2 × 2,592,000 × 2 = 6.9 GB
```

**Optimization strategies:**
- Increase scrape interval for non-critical metrics
- Use recording rules to pre-aggregate
- Drop unnecessary metrics with relabeling
- Use compression (enabled by default)
- Archive old data to S3 (use Thanos or Cortex)

### Compute Costs

**Right-size Prometheus:**
```bash
# Monitor actual resource usage
kubectl top pod -n monitoring

# Adjust resources based on actual usage + 30% headroom
resources:
  requests:
    cpu: <actual_usage × 1.3>
    memory: <actual_usage × 1.3>
```

**Use node affinity for cost savings:**
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - t3.large  # Cheaper instance type
```

### LoadBalancer Costs

**Use Ingress instead of LoadBalancer:**
```yaml
# Instead of LoadBalancer service ($20/month)
# Use Ingress with shared ALB ($15/month + $0.008/LCU-hour)
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
```

## Troubleshooting

### Common Issues

**1. Prometheus not scraping targets**

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n locust -o yaml

# Verify label selectors match
kubectl get svc -n locust --show-labels

# Check Prometheus logs
kubectl logs -n monitoring statefulset/prometheus-prometheus-kube-prometheus-prometheus

# View targets in Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets
```

**2. High memory usage in Prometheus**

```bash
# Check cardinality
curl http://localhost:9090/api/v1/status/tsdb

# Find high-cardinality metrics
topk(10, count by (__name__)({__name__=~".+"}))

# Drop high-cardinality labels
metric_relabel_configs:
  - regex: 'user_id|session_id'
    action: labeldrop
```

**3. Grafana dashboard shows "No data"**

```bash
# Test Prometheus datasource
curl -X POST http://localhost:3000/api/datasources/proxy/1/api/v1/query \
  -H "Content-Type: application/json" \
  -d '{"query":"up"}'

# Check query in Grafana Explore tab
# Verify time range matches data availability
# Check Prometheus has data: kubectl port-forward ... and query directly
```

**4. Alerts not firing**

```bash
# Check PrometheusRule syntax
kubectl get prometheusrule -n monitoring -o yaml

# View alerts in Prometheus UI
http://localhost:9090/alerts

# Check AlertManager configuration
kubectl get secret alertmanager-prometheus-kube-prometheus-alertmanager \
  -n monitoring -o yaml

# View AlertManager logs
kubectl logs -n monitoring statefulset/alertmanager-prometheus-kube-prometheus-alertmanager
```

### Debug Queries

**Check metric availability:**
```promql
# List all metrics
{__name__=~"locust_.*"}

# Check specific metric
locust_requests_total

# Check label values
label_values(locust_requests_total, endpoint)
```

**Test rate calculations:**
```promql
# Raw counter value (not useful for graphing)
locust_requests_total

# Rate over 5 minutes (requests per second)
rate(locust_requests_total[5m])

# Total requests in last 5 minutes
increase(locust_requests_total[5m])
```

**Verify histogram buckets:**
```promql
# Show all buckets
locust_response_time_seconds_bucket

# Calculate p95
histogram_quantile(0.95, rate(locust_response_time_seconds_bucket[5m]))
```

## Summary Checklist

### Metrics
- [ ] Label cardinality < 1,000 per metric
- [ ] Use appropriate metric types (counter, gauge, histogram)
- [ ] Follow naming conventions
- [ ] Configure sensible histogram buckets
- [ ] Use recording rules for expensive queries

### Dashboards
- [ ] Organize by audience (exec, ops, engineering)
- [ ] Use appropriate visualizations
- [ ] Show rate of change, not absolute counters
- [ ] Use percentiles (p95, p99), not just averages
- [ ] Include time range variables
- [ ] Add deployment/incident annotations

### Alerts
- [ ] Every alert is actionable
- [ ] Include runbook links
- [ ] Use appropriate severity levels
- [ ] Set sensible thresholds and durations
- [ ] Group related alerts
- [ ] Test alert routing

### Performance
- [ ] Right-size Prometheus resources
- [ ] Use recording rules for dashboards
- [ ] Adjust scrape intervals appropriately
- [ ] Drop unnecessary metrics
- [ ] Monitor Prometheus performance

### Security
- [ ] Enable authentication (Grafana, Prometheus)
- [ ] Use HTTPS/TLS for external access
- [ ] Implement Network Policies
- [ ] Use RBAC for Kubernetes access
- [ ] Scrub sensitive data from metrics

### Cost
- [ ] Optimize storage retention
- [ ] Use Ingress instead of LoadBalancer
- [ ] Right-size compute resources
- [ ] Use spot instances for non-critical components
- [ ] Archive old data to S3

## Additional Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)
- [Google SRE Book - Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [PromQL for Humans](https://timber.io/blog/promql-for-humans/)
- [RED Method](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)
- [USE Method](http://www.brendangregg.com/usemethod.html)
