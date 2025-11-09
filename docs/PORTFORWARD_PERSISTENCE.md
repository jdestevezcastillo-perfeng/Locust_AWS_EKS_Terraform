# Persistent Port-Forward Setup Guide

## Overview

This project includes an **automatic, self-healing port-forward system** that keeps all services accessible 24/7. Port-forwards start automatically on boot, survive pod redeployments, and recover automatically if they fail.

**Status:** ✅ All services operational and persistent

## Quick Access

All services are automatically available at:

| Service | URL | Port | Status |
|---------|-----|------|--------|
| **Locust Web UI** | http://localhost:8089 | 8089 | Active ✅ |
| **Locust Metrics** | http://localhost:9091/metrics | 9091 | Active ✅ |
| **Grafana** | http://localhost:3000 | 3000 | Active ✅ |
| **Prometheus** | http://localhost:9090 | 9090 | Active ✅ |

## How It Works

### 1. Service-Based Port-Forwards

Instead of forwarding to specific pod names (which change on redeployment), we forward to **Kubernetes services**:

```bash
kubectl port-forward -n locust svc/locust-master 8089:8089
kubectl port-forward -n locust svc/locust-master 9091:8090
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
kubectl port-forward -n monitoring svc/prometheus-grafana-kube-pr-prometheus 9090:9090
```

Services automatically route to the current pod, so port-forwards survive pod restarts.

### 2. Persistent Startup via systemd

Four systemd services automatically start the port-forwards on boot:

```
/etc/systemd/system/locust-portforward-persistent.service
/etc/systemd/system/monitoring-portforward-persistent.service
```

### 3. Health Checks with Automatic Recovery

Two systemd timers run health checks every minute:

```
/etc/systemd/system/locust-portforward-health.timer
/etc/systemd/system/monitoring-portforward-health.timer
```

If any port becomes unreachable:
1. Health check detects failure
2. Automatic restart script is triggered
3. New port-forwards are established
4. Services are restored within 60 seconds

## Components

### Startup Scripts

**`/usr/local/bin/start-locust-portforward.sh`**
- Kills existing port-forwards (to prevent conflicts)
- Starts new port-forwards using nohup (survives terminal closure)
- Tests connectivity to both ports
- Stores PID information for monitoring

**`/usr/local/bin/start-monitoring-portforward.sh`**
- Same as above for Grafana and Prometheus
- Handles monitoring namespace services

### Health Check Scripts

**`/usr/local/bin/check-locust-portforward.sh`**
- Tests Locust Web UI (port 8089)
- Tests Locust Metrics (port 9091)
- Automatically restarts if either is down

**`/usr/local/bin/check-monitoring-portforward.sh`**
- Tests Grafana (port 3000)
- Tests Prometheus (port 9090)
- Automatically restarts if either is down

### Systemd Services

**Startup Services** (run once at boot):
```
locust-portforward-persistent.service
monitoring-portforward-persistent.service
```

**Health Check Services** (triggered by timers):
```
locust-portforward-health.service
monitoring-portforward-health.service
```

**Health Check Timers** (every 1 minute):
```
locust-portforward-health.timer
monitoring-portforward-health.timer
```

## Monitoring & Logs

### Health Check Logs

Check if port-forwards are healthy:

```bash
# Locust port-forwards
tail -f /var/log/locust-portforward-health.log

# Monitoring port-forwards
tail -f /var/log/monitoring-portforward-health.log
```

### Port-Forward Logs

Each port-forward has its own log:

```bash
tail -f /var/log/locust-portforward-8089.log
tail -f /var/log/locust-portforward-9091.log
tail -f /var/log/grafana-portforward.log
tail -f /var/log/prometheus-portforward.log
```

### Check Running Processes

Verify all port-forwards are running:

```bash
ps aux | grep "kubectl port-forward" | grep -v grep
```

Expected output (4 processes):
```
kubectl port-forward -n locust svc/locust-master 8089:8089
kubectl port-forward -n locust svc/locust-master 9091:8090
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
kubectl port-forward -n monitoring svc/prometheus-grafana-kube-pr-prometheus 9090:9090
```

### Check Service Status

```bash
systemctl status locust-portforward-persistent.service
systemctl status monitoring-portforward-persistent.service
systemctl status locust-portforward-health.timer
systemctl status monitoring-portforward-health.timer
```

## Manual Operations

### Manually Restart Port-Forwards

If you need to restart all port-forwards immediately:

```bash
# For Locust
/usr/local/bin/start-locust-portforward.sh

# For Monitoring
/usr/local/bin/start-monitoring-portforward.sh

# For both
/usr/local/bin/start-locust-portforward.sh && \
/usr/local/bin/start-monitoring-portforward.sh
```

### Manually Run Health Checks

Trigger health checks without waiting for the timer:

```bash
# For Locust
/usr/local/bin/check-locust-portforward.sh

# For Monitoring
/usr/local/bin/check-monitoring-portforward.sh
```

### Disable Auto-Recovery (Not Recommended)

If you want to disable automatic recovery for testing:

```bash
systemctl stop locust-portforward-health.timer
systemctl stop monitoring-portforward-health.timer
```

Re-enable with:

```bash
systemctl start locust-portforward-health.timer
systemctl start monitoring-portforward-health.timer
```

## Troubleshooting

### Services Not Accessible

**Check if port-forwards are running:**
```bash
ps aux | grep "kubectl port-forward" | grep -v grep
```

If empty, restart them:
```bash
/usr/local/bin/start-locust-portforward.sh
/usr/local/bin/start-monitoring-portforward.sh
```

### Port Already in Use

If a port is already in use by another process:

```bash
# Find what's using the port (e.g., port 8089)
lsof -i :8089

# Kill the process (replace PID with actual PID)
kill -9 <PID>

# Then restart port-forwards
/usr/local/bin/start-locust-portforward.sh
```

### Services Fail to Start

**Check for service-related issues:**
```bash
# Verify services exist
kubectl get svc -n locust
kubectl get svc -n monitoring

# Check if master/monitoring pods are running
kubectl get pods -n locust
kubectl get pods -n monitoring

# View pod logs if they're not running
kubectl logs deployment/locust-master -n locust
kubectl logs deployment/prometheus-grafana -n monitoring
```

### Health Checks Show Failures

**Check the health check logs:**
```bash
tail -20 /var/log/locust-portforward-health.log
tail -20 /var/log/monitoring-portforward-health.log
```

**Manually test connectivity:**
```bash
curl http://localhost:8089/
curl http://localhost:9091/metrics
curl http://localhost:3000/
curl http://localhost:9090/
```

If any fail:
1. Check if the service pod is running: `kubectl get pods -n <namespace>`
2. Check pod logs: `kubectl logs -n <namespace> <pod-name>`
3. Verify service exists: `kubectl get svc -n <namespace>`

## Performance Impact

The persistent port-forward system is lightweight:

- **CPU:** < 0.1% per port-forward
- **Memory:** ~50MB per port-forward
- **Health Checks:** Every 60 seconds, takes ~1 second
- **Network:** Minimal (health checks only use curl)

## Security Considerations

- Port-forwards use localhost only (not exposed externally)
- Requires local kubectl access to work
- Health checks use HTTP (internal only)
- Logs stored locally with standard permissions

For production:
- Restrict access to `/usr/local/bin/start-*.sh` and `/usr/local/bin/check-*.sh`
- Regularly audit logs
- Monitor systemd timers
- Consider authentication for exposed services

## Integration with Monitoring

The port-forward health is tracked in logs:

```bash
# View all health check events
grep "Locust\|Grafana\|Prometheus" /var/log/locust-portforward-health.log /var/log/monitoring-portforward-health.log | sort
```

You can integrate these logs with your monitoring system:
- Ship logs to CloudWatch, DataDog, etc.
- Set up alerts for repeated failures
- Dashboard to visualize port-forward health

## Frequently Asked Questions

### Q: Will port-forwards survive pod restarts?
**A:** Yes! We use service-based forwarding, which automatically routes to the new pod.

### Q: Do I need to keep a terminal open?
**A:** No! Port-forwards use `nohup` and are managed by systemd, so they run independently.

### Q: What if I reboot my machine?
**A:** Port-forwards automatically restart on boot via systemd services.

### Q: Can I customize which ports are used?
**A:** Yes, edit the startup scripts:
- `/usr/local/bin/start-locust-portforward.sh`
- `/usr/local/bin/start-monitoring-portforward.sh`

Change the port numbers and restart.

### Q: How do I check if everything is working?
**A:** Run this test:
```bash
echo "Locust UI:" && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8089/
echo "Locust Metrics:" && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9091/metrics
echo "Grafana:" && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/
echo "Prometheus:" && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9090/
```

All should return `200` or `302` (redirect).

### Q: How often are health checks run?
**A:** Every 1 minute (60 seconds). Adjust in systemd timer files if needed.

### Q: Can I disable health checks?
**A:** Yes, but not recommended:
```bash
systemctl stop locust-portforward-health.timer
systemctl stop monitoring-portforward-health.timer
```

## Next Steps

1. **Verify Setup:** Test all access points
2. **Monitor Logs:** Check health check logs regularly
3. **Create Alerts:** Set up notifications for health check failures
4. **Document Access:** Share URLs with your team
5. **Backup:** Store port-forward scripts in version control

## Support & Troubleshooting

For detailed troubleshooting:
1. Check all log files mentioned above
2. Verify pod and service status: `kubectl get pods,svc -n locust,monitoring`
3. Test curl commands to each service
4. Check systemd status: `systemctl status locust-portforward-*`
5. Review health check scripts for any custom configuration

## References

- **Startup Scripts:** `/usr/local/bin/start-*.sh`
- **Health Checks:** `/usr/local/bin/check-*.sh`
- **Systemd Services:** `/etc/systemd/system/*-portforward*.service`
- **Systemd Timers:** `/etc/systemd/system/*-portforward*.timer`
- **Logs:** `/var/log/*-portforward*.log`
