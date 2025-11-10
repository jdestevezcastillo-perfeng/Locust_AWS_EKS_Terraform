# Monitoring Stack - Quick Reference Card

## Deployment

### GitHub Actions Workflow
```bash
# Via GitHub UI: Actions > Deploy Monitoring Stack > Run workflow

# Via GitHub CLI
gh workflow run deploy-monitoring.yml \
  --field aws-region=eu-central-1 \
  --field retention-days=30 \
  --field storage-size=50
```

### Manual Deployment
```bash
# Using existing script
./scripts/observability/setup-prometheus-grafana.sh
```

## Access Services

### Prometheus
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090
```

### Grafana
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-grafana 3000:80
# http://localhost:3000
# Username: admin
# Password: [from GRAFANA_ADMIN_PASSWORD secret]
```

### AlertManager
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
# http://localhost:9093
```

## Key Metrics

### Locust Metrics
```promql
# Current users
locust_users

# Request rate (RPS)
rate(locust_requests_total[5m])

# Error rate (%)
(rate(locust_requests_num_failures[5m]) / rate(locust_requests_total[5m])) * 100

# 95th percentile response time
histogram_quantile(0.95, rate(locust_response_time_seconds_bucket[5m]))

# Average response time
locust_requests_avg_response_time
```

### Kubernetes Metrics
```promql
# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="locust"}[5m])) by (pod)

# Pod memory usage
sum(container_memory_usage_bytes{namespace="locust"}) by (pod)

# Pod count
count(kube_pod_status_phase{namespace="locust", phase="Running"})
```

## Useful Commands

### Status Checks
```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Check Locust ServiceMonitor
kubectl get servicemonitor -n locust

# Check Prometheus rules
kubectl get prometheusrules -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets
```

### Logs
```bash
# Prometheus logs
kubectl logs -n monitoring statefulset/prometheus-prometheus-kube-prometheus-prometheus

# Grafana logs
kubectl logs -n monitoring deployment/prometheus-kube-prometheus-grafana

# AlertManager logs
kubectl logs -n monitoring statefulset/alertmanager-prometheus-kube-prometheus-alertmanager

# Prometheus Operator logs
kubectl logs -n monitoring deployment/prometheus-kube-prometheus-operator
```

### Troubleshooting
```bash
# Restart Prometheus
kubectl rollout restart statefulset/prometheus-prometheus-kube-prometheus-prometheus -n monitoring

# Restart Grafana
kubectl rollout restart deployment/prometheus-kube-prometheus-grafana -n monitoring

# Check Prometheus configuration
kubectl get secret prometheus-prometheus-kube-prometheus-prometheus -n monitoring -o yaml

# Check ServiceMonitor labels
kubectl get svc -n locust --show-labels
```

## Alert Rules

| Alert | Severity | Threshold | Duration |
|-------|----------|-----------|----------|
| LocustMasterDown | critical | up == 0 | 5m |
| LocustHighErrorRate | warning | error rate > 10% | 5m |
| LocustHighResponseTime | warning | avg response > 5s | 5m |
| LocustHighMemoryUsage | warning | memory > 85% | 5m |
| LocustWorkerRestarts | warning | restarts > 0 | 5m |

## Dashboards

### Locust Load Testing
- **UID:** locust-load-testing
- **Location:** Dashboards > Locust folder
- **Refresh:** 10 seconds
- **Panels:**
  - Master status
  - Request rate
  - Error rate %
  - Response times (avg, min, max)
  - Active users & workers

### Kubernetes Cluster
- **ID:** 7249 (Grafana.com)
- **Metrics:** Cluster resources, nodes, pods

### Kubernetes Pods
- **ID:** 6417 (Grafana.com)
- **Metrics:** Per-pod resources, containers

## Configuration

### Storage
```yaml
Prometheus: 50Gi (default)
Grafana: 10Gi (default)
Retention: 30 days (default)
```

### Resources
```yaml
Prometheus:
  CPU: 2 cores (request), 4 cores (limit)
  Memory: 8Gi (request), 16Gi (limit)

Grafana:
  CPU: 100m (request), 200m (limit)
  Memory: 128Mi (request), 256Mi (limit)
```

### Scrape Intervals
```yaml
Locust: 15 seconds
Kubernetes pods: 30 seconds
Node exporter: 60 seconds
```

## GitHub Secrets Required

```bash
AWS_ACCESS_KEY_ID              # Required
AWS_SECRET_ACCESS_KEY          # Required
GRAFANA_ADMIN_PASSWORD         # Optional (default: admin123)
```

## Cost Estimate

| Component | Cost/Month |
|-----------|-----------|
| Prometheus (50Gi EBS) | ~$5 |
| Grafana (10Gi EBS) | ~$1 |
| LoadBalancer (optional) | ~$16 |
| **Total** | **~$6-22** |

## Support

- **Documentation:** `.github/README.md`
- **Best Practices:** `docs/MONITORING_BEST_PRACTICES.md`
- **Full Summary:** `MONITORING_DEPLOYMENT_SUMMARY.md`

## Quick Links

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000
- AlertManager: http://localhost:9093
- Targets: http://localhost:9090/targets
- Alerts: http://localhost:9090/alerts
- Rules: http://localhost:9090/rules
