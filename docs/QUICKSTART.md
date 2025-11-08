# Quick Start Guide

This is a quick reference for deploying Locust on AWS EKS. For the comprehensive guide, see [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md).

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5
- kubectl >= 1.28
- Docker running
- jq installed

## One-Command Deployment

```bash
./scripts/deploy.sh
```

This single command will:
1. Deploy AWS infrastructure (VPC, EKS, ECR)
2. Build and push Docker image
3. Deploy Locust to Kubernetes
4. Display the web UI URL

**Time:** 25-30 minutes
**Cost:** ~$0.34/hour while running

## Access Locust Web UI

After deployment completes, access the web interface at the URL shown:

```
http://<loadbalancer-url>:8089
```

Or retrieve it anytime:

```bash
kubectl get svc locust-master -n locust
```

## Useful Commands

```bash
# View pod status
kubectl get pods -n locust

# View master logs
kubectl logs -f deployment/locust-master -n locust

# View worker logs
kubectl logs -f deployment/locust-worker -n locust

# Check autoscaler status
kubectl get hpa -n locust

# Monitor pod metrics
kubectl top pods -n locust

# Verify deployment
./scripts/verify-deployment.sh
```

## Change Test Target

Edit the ConfigMap to change the target API:

```bash
kubectl edit configmap locust-config -n locust

# Change:
# TARGET_HOST: "https://httpbin.org"
# LOCUST_SCENARIO: "httpbin"

# Restart deployments
kubectl rollout restart deployment/locust-master -n locust
kubectl rollout restart deployment/locust-worker -n locust
```

## Cleanup (Important!)

```bash
./scripts/destroy.sh
```

**Always destroy resources when not in use to avoid charges!**

## Project Structure

```
.
├── SRE_DEPLOYMENT_GUIDE.md    # Comprehensive guide
├── QUICKSTART.md              # This file
├── terraform/                 # Infrastructure as Code
│   ├── main.tf               # VPC, EKS, ECR
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Output values
│   └── terraform.tfvars      # Configuration
├── docker/                    # Container configuration
│   ├── Dockerfile            # Multi-stage build
│   └── entrypoint.sh         # Master/worker startup
├── locust/                    # Test scenarios
│   ├── locustfile.py         # Scenario loader
│   └── scenarios/
│       ├── jsonplaceholder.py
│       ├── httpbin.py
│       └── custom.py
├── kubernetes/                # K8s manifests
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── master-deployment.yaml
│   ├── master-service.yaml
│   ├── worker-deployment.yaml
│   └── worker-hpa.yaml
└── scripts/                   # Automation
    ├── deploy.sh             # Full deployment
    ├── destroy.sh            # Cleanup
    ├── build-and-push.sh     # Docker build
    └── verify-deployment.sh  # Health check
```

## Test Scenarios

Three scenarios are included:

1. **jsonplaceholder** (default): Tests JSONPlaceholder API
2. **httpbin**: Tests HTTPBin API (various HTTP operations)
3. **custom**: Template for your own API

Switch scenarios by editing `kubernetes/configmap.yaml`:

```yaml
data:
  LOCUST_SCENARIO: "httpbin"  # Change this
  TARGET_HOST: "https://httpbin.org"
```

## Troubleshooting

### LoadBalancer stays in "pending"
Wait 2-3 minutes. Check with: `kubectl describe svc locust-master -n locust`

### Pods not starting
Check logs: `kubectl logs <pod-name> -n locust`
Check events: `kubectl get events -n locust --sort-by='.lastTimestamp'`

### HPA shows "unknown"
Install metrics server:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Workers can't connect to master
Check DNS: `kubectl exec -it deployment/locust-worker -n locust -- nslookup locust-master`

## Cost Management

| Resource | Hourly | Monthly (24/7) |
|----------|--------|----------------|
| EKS Control Plane | $0.10 | $73 |
| 3x t3.medium | $0.125 | $90 |
| NAT Gateways | $0.09 | $65 |
| LoadBalancer | $0.023 | $16 |
| **Total** | **$0.34** | **$244** |

**CRITICAL:** Run `./scripts/destroy.sh` when finished testing!

## Next Steps

1. Read [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md) for detailed explanations
2. Customize `locust/scenarios/custom.py` for your API
3. Integrate with CI/CD pipeline
4. Set up CloudWatch alarms for cost monitoring
5. Configure Prometheus/Grafana for advanced metrics

## Support

For detailed troubleshooting, architecture decisions, and production considerations, see the comprehensive SRE guide.
