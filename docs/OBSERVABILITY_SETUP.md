# Observability Setup Guide

## Overview

This guide provides instructions for setting up Prometheus and Grafana observability for monitoring your Locust load testing cluster on AWS EKS.

**Prerequisites:**
- AWS EKS cluster deployed and running (via `./deploy.sh`)
- `kubectl` configured and authenticated to your cluster
- `helm` 3.0+ installed locally
- Locust workloads running in the `locust` namespace

## Quick Start

### 1. Deploy Observability Stack

After your main EKS deployment is complete, run:

```bash
./scripts/observability/setup-prometheus-grafana.sh
```

This script will:
- Create a `monitoring` namespace
- Add Prometheus Community Helm charts
- Deploy Prometheus, Grafana, AlertManager, and supporting components
- Configure auto-discovery of Locust metrics
- Set up default dashboards

**Estimated time: 5-10 minutes**

### 2. Access Grafana

Once deployment completes, port-forward to Grafana:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Then access: **http://localhost:3000**

**Default credentials:**
- Username: `admin`
- Password: `admin123` (change this in production!)

### 3. Access Prometheus

Port-forward to Prometheus:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 9090:9090
```

Access: **http://localhost:9090**

## Components Deployed

### Prometheus
- **Purpose:** Metrics collection and storage
- **Retention:** 30 days
- **Storage:** 50GB persistent volume
- **Targets:**
  - Locust master pod metrics
  - Kubernetes pod metrics
  - Node exporter metrics

### Grafana
- **Purpose:** Visualization and dashboards
- **Storage:** 10GB persistent volume
- **Pre-configured Dashboards:**
  - Kubernetes Cluster Overview
  - Kubernetes Nodes
  - Locust Load Testing Dashboard

### AlertManager
- **Purpose:** Alert routing and grouping
- **Configuration:** Default receivers configured
- **Alerts:** High error rates, master pod down, high memory usage

### Node Exporter
- **Purpose:** Node-level system metrics
- **Metrics:** CPU, memory, disk, network metrics

### Kube State Metrics
- **Purpose:** Kubernetes resource metrics
- **Metrics:** Pod status, resource allocation, scaling events

## Monitoring Locust Metrics

### Available Metrics

The following Locust metrics are automatically scraped:

- `locust_requests_total` - Total number of requests
- `locust_requests_failed_total` - Total failed requests
- `locust_requests_success_total` - Total successful requests
- `locust_requests_avg_response_time_ms` - Average response time
- `locust_requests_max_response_time_ms` - Max response time
- `locust_requests_min_response_time_ms` - Min response time

### Querying Metrics

Examples of useful queries in Prometheus:

```promql
# Current number of users
locust_users

# Request rate (requests per second)
rate(locust_requests_total[1m])

# Error rate percentage
(sum(rate(locust_requests_failed_total[5m])) / sum(rate(locust_requests_total[5m]))) * 100

# Average response time
histogram_quantile(0.5, locust_requests_duration_ms)

# P95 response time
histogram_quantile(0.95, locust_requests_duration_ms)

# P99 response time
histogram_quantile(0.99, locust_requests_duration_ms)
```

### Creating Custom Dashboards

1. Log in to Grafana
2. Click **+** → **Dashboard** → **Add new panel**
3. Select Prometheus as the data source
4. Write your PromQL query
5. Customize visualization (chart type, colors, etc.)
6. Save dashboard

## Alert Configuration

Pre-configured alerts:

### LocustMasterDown
- **Triggers:** Locust master pod not responding
- **Duration:** 5 minutes
- **Severity:** Critical

### HighErrorRate
- **Triggers:** Error rate > 10% for 5 minutes
- **Severity:** Warning

### HighMemoryUsage
- **Triggers:** Locust pods memory usage > 80% for 5 minutes
- **Severity:** Warning

### Configuring Alert Receivers

To add email, Slack, or other alert receivers:

1. Port-forward to Grafana
2. Go to **Alerting** → **Notification Channels**
3. Click **New Channel**
4. Select channel type (Email, Slack, PagerDuty, etc.)
5. Configure and save

## Useful Commands

### View monitoring pods
```bash
kubectl get pods -n monitoring
```

### View Prometheus logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -f
```

### View Grafana logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -f
```

### Check Prometheus targets
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 9090:9090
# Visit http://localhost:9090/targets
```

### Check AlertManager
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 9093:9093
# Visit http://localhost:9093
```

### Verify Locust metrics are being scraped
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 9090:9090
# Visit http://localhost:9090/graph
# Search for "locust_" metrics
```

## Persistent Storage

Both Prometheus and Grafana use persistent volumes:
- **Prometheus:** 50GB (configurable in script)
- **Grafana:** 10GB (configurable in script)

These persist data across pod restarts.

## Customization

### Changing Admin Password

Before deployment:
```bash
export GRAFANA_ADMIN_PASSWORD="your-secure-password"
./scripts/observability/setup-prometheus-grafana.sh
```

Or after deployment, use Grafana UI:
1. Log in
2. Go to **Configuration** → **Users**
3. Click **Admin**
4. Change password

### Adjusting Prometheus Retention

Edit `scripts/observability/setup-prometheus-grafana.sh`:

```yaml
retention: 30d  # Change this value
```

Then re-run the script.

### Adding Custom Scrape Targets

Edit the Helm values in the script to add more scrape configs:

```yaml
additionalScrapeConfigs:
  - job_name: 'your-app'
    static_configs:
      - targets: ['your-app-service:port']
```

## Troubleshooting

### Pods not starting
```bash
# Check pod logs
kubectl logs -n monitoring <pod-name>

# Check pod events
kubectl describe pod -n monitoring <pod-name>

# Check available resources
kubectl describe nodes
```

### Prometheus not scraping targets
```bash
# Check targets in Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-grafana 9090:9090
# Visit http://localhost:9090/targets

# View Prometheus configuration
kubectl get cm -n monitoring prometheus-grafana-prometheus -o yaml
```

### Grafana not connecting to Prometheus
```bash
# Verify Prometheus service is running
kubectl get svc -n monitoring

# Test connectivity
kubectl run -it --rm debug --image=alpine --restart=Never -n monitoring -- sh
# Inside pod: wget http://prometheus-operated:9090
```

### Storage issues
```bash
# Check PVC status
kubectl get pvc -n monitoring

# Check disk usage
kubectl exec -n monitoring <prometheus-pod> -- du -sh /prometheus
```

## Production Considerations

### Security
1. **Change default Grafana password immediately**
2. **Enable HTTPS/TLS** for Grafana access
3. **Use authentication** (OAuth2, LDAP, etc.)
4. **Restrict RBAC** permissions for monitoring namespace
5. **Enable pod security policies** if applicable

### High Availability
1. Deploy multiple Prometheus replicas using StatefulSets
2. Use Prometheus HA with AlertManager for redundancy
3. Consider Thanos for long-term storage and querying

### Resource Management
1. **Set resource requests/limits** for Prometheus and Grafana
2. **Monitor storage** growth and adjust retention accordingly
3. **Implement data retention policies** based on compliance needs

### Backup & Recovery
```bash
# Backup Grafana dashboards
kubectl exec -n monitoring <grafana-pod> -- grafana-cli admin export-dashboard > backup.json

# Backup Prometheus data
kubectl exec -n monitoring <prometheus-pod> -- tar czf /tmp/prometheus-backup.tar.gz /prometheus
kubectl cp monitoring/<prometheus-pod>:/tmp/prometheus-backup.tar.gz ./prometheus-backup.tar.gz
```

## Cleanup

To remove all observability components:

```bash
./scripts/observability/cleanup-observability.sh
```

Or force cleanup without prompts:

```bash
./scripts/observability/cleanup-observability.sh --force
```

This will:
- Uninstall Prometheus, Grafana, and related services
- Delete the monitoring namespace
- Remove monitoring manifests
- Clean up configuration files

## Integration with Existing Systems

### CloudWatch Integration
To export metrics to AWS CloudWatch:

```bash
# Install CloudWatch exporter
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install cloudwatch-exporter prometheus-community/prometheus-cloudwatch-exporter \
  -n monitoring
```

### Elasticsearch/ELK Stack
To send logs to Elasticsearch:

```bash
# Install Fluent Bit for log forwarding
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit \
  -n monitoring \
  -f values.yaml
```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kube Prometheus Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [PromQL Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)

## Support

For issues with observability setup:

1. Check pod logs: `kubectl logs -n monitoring <pod-name>`
2. Verify connectivity between components
3. Check Prometheus targets and metrics
4. Review Grafana data source configuration
5. Consult the references above

## Next Steps

After setting up observability:

1. **Create custom dashboards** for your specific use cases
2. **Configure alerts** for critical metrics
3. **Set up notifications** (email, Slack, etc.)
4. **Document your metrics** and thresholds
5. **Train team members** on using Grafana and Prometheus
6. **Implement runbooks** for alert responses
