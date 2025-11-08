# Distributed Locust Load Testing on AWS EKS

Production-ready infrastructure for running distributed Locust load tests on Amazon EKS with Terraform automation.

## Overview

This project provides a complete, enterprise-grade solution for deploying Locust load testing infrastructure on AWS. It includes:

- Full AWS infrastructure automation with Terraform
- Multi-zone, highly available EKS cluster
- Auto-scaling Locust workers (3-20 replicas)
- Multiple test scenarios (JSONPlaceholder, HTTPBin, custom)
- Comprehensive monitoring with CloudWatch
- Single-command deployment and destruction
- Production security hardening (private subnets, non-root containers)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Region                           │
│                      (eu-central-1)                          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                    │ │
│  │                                                          │ │
│  │  ┌──────────────────┐     ┌──────────────────┐         │ │
│  │  │  Public Subnet   │     │  Public Subnet   │         │ │
│  │  │  (AZ-1)          │     │  (AZ-2)          │         │ │
│  │  │  ┌────────────┐  │     │  ┌────────────┐  │         │ │
│  │  │  │ NAT Gateway│  │     │  │ NAT Gateway│  │         │ │
│  │  │  └────────────┘  │     │  └────────────┘  │         │ │
│  │  │  ┌────────────┐  │     │  ┌────────────┐  │         │ │
│  │  │  │     NLB    │  │     │  │            │  │         │ │
│  │  │  └────────────┘  │     │  └────────────┘  │         │ │
│  │  └──────────────────┘     └──────────────────┘         │ │
│  │           │                         │                   │ │
│  │  ┌────────┴──────────┐     ┌───────┴───────────┐       │ │
│  │  │  Private Subnet   │     │  Private Subnet   │       │ │
│  │  │  (AZ-1)           │     │  (AZ-2)           │       │ │
│  │  │  ┌─────────────┐  │     │  ┌─────────────┐  │       │ │
│  │  │  │ EKS Worker  │  │     │  │ EKS Worker  │  │       │ │
│  │  │  │  Node 1     │  │     │  │  Node 2     │  │       │ │
│  │  │  │             │  │     │  │             │  │       │ │
│  │  │  │ ┌─────────┐ │  │     │  │ ┌─────────┐ │  │       │ │
│  │  │  │ │ Locust  │ │  │     │  │ │ Locust  │ │  │       │ │
│  │  │  │ │ Master  │ │  │     │  │ │ Workers │ │  │       │ │
│  │  │  │ └─────────┘ │  │     │  │ └─────────┘ │  │       │ │
│  │  │  └─────────────┘  │     │  └─────────────┘  │       │ │
│  │  └──────────────────┘     └──────────────────┘         │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │   EKS Cluster    │  │  ECR Repository  │                │
│  │   (Control Plane)│  │  (Docker Images) │                │
│  └──────────────────┘  └──────────────────┘                │
│                                                              │
│  ┌──────────────────────────────────────────────────────────┐│
│  │            CloudWatch Logs & Metrics                     ││
│  └──────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

```bash
# Install required tools
brew install awscli terraform kubectl jq

# Configure AWS credentials
aws configure

# Verify Docker is running
docker info
```

### Deploy Everything (One Command)

```bash
./scripts/deploy.sh
```

This command will:
1. Deploy AWS infrastructure (VPC, EKS, ECR) - **20 minutes**
2. Build and push Docker image - **3 minutes**
3. Deploy Locust to Kubernetes - **2 minutes**

**Total time: ~25 minutes**

### Access Locust Web UI

```bash
# Get LoadBalancer URL
kubectl get svc locust-master -n locust

# Access at: http://<EXTERNAL-IP>:8089
```

### Destroy Everything

```bash
./scripts/destroy.sh
```

**CRITICAL:** Always destroy resources when not in use to avoid charges (~$0.34/hour)

## Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [QUICKSTART.md](QUICKSTART.md) | Quick reference and common commands | All users |
| [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md) | Comprehensive 60-page guide with architecture decisions | SRE/DevOps engineers |
| [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) | Complete file inventory and checklists | Team leads, auditors |

## Project Structure

```
.
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # VPC, EKS, ECR, CloudWatch
│   ├── variables.tf       # Configurable parameters
│   ├── outputs.tf         # Export values for scripts
│   └── terraform.tfvars   # Environment configuration
│
├── docker/                 # Container configuration
│   ├── Dockerfile         # Multi-stage production build
│   └── entrypoint.sh      # Master/worker startup logic
│
├── locust/                 # Load test scenarios
│   ├── locustfile.py      # Scenario loader
│   └── scenarios/
│       ├── jsonplaceholder.py  # JSONPlaceholder API tests
│       ├── httpbin.py          # HTTPBin API tests
│       └── custom.py           # Template for custom APIs
│
├── kubernetes/             # K8s manifests
│   ├── namespace.yaml
│   ├── configmap.yaml     # Test configuration
│   ├── master-deployment.yaml
│   ├── master-service.yaml     # LoadBalancer
│   ├── worker-deployment.yaml
│   └── worker-hpa.yaml         # Horizontal Pod Autoscaler
│
├── scripts/                # Automation
│   ├── deploy.sh          # Full deployment orchestration
│   ├── destroy.sh         # Complete cleanup
│   ├── build-and-push.sh  # Docker build + ECR push
│   └── verify-deployment.sh    # Health checks
│
└── docs/                   # Documentation
    ├── QUICKSTART.md
    ├── SRE_DEPLOYMENT_GUIDE.md
    └── DEPLOYMENT_SUMMARY.md
```

## Key Features

### Infrastructure

- **Multi-AZ Deployment:** High availability across 2 availability zones
- **Private Worker Nodes:** Isolated in private subnets for security
- **NAT Gateways:** Secure outbound internet access for API calls
- **Auto-Scaling:** 3-10 EC2 nodes, managed by EKS
- **CloudWatch Integration:** Centralized logs and metrics

### Kubernetes

- **Master-Worker Architecture:** 1 master coordinator, 3-20 workers
- **Horizontal Pod Autoscaling:** CPU/memory-based auto-scaling
- **Resource Limits:** Prevents resource exhaustion
- **Health Checks:** Automatic pod restart on failure
- **LoadBalancer Service:** External access to web UI

### Security

- **Non-Root Containers:** Runs as UID 1000 (locust user)
- **Private Subnets:** Worker nodes have no public IPs
- **Security Groups:** Granular network access control
- **IAM Roles:** Least-privilege access for EKS nodes
- **ECR Private Registry:** Images never exposed publicly

### Operations

- **Single-Command Deployment:** `./scripts/deploy.sh`
- **Single-Command Destruction:** `./scripts/destroy.sh`
- **Health Verification:** `./scripts/verify-deployment.sh`
- **Image Versioning:** Supports git SHA tags for traceability

## Test Scenarios

Three scenarios included out-of-the-box:

### 1. JSONPlaceholder (Default)
```yaml
TARGET_HOST: "https://jsonplaceholder.typicode.com"
LOCUST_SCENARIO: "jsonplaceholder"
```

Tests typical REST API operations:
- GET /posts (list)
- GET /posts/{id} (single)
- GET /posts/{id}/comments
- POST /posts (create)
- PUT /posts/{id} (update)

### 2. HTTPBin
```yaml
TARGET_HOST: "https://httpbin.org"
LOCUST_SCENARIO: "httpbin"
```

Tests various HTTP operations:
- GET with query parameters
- POST with JSON/form data
- Custom headers
- Basic authentication
- Status codes
- Delays and timeouts
- Gzip compression

### 3. Custom (Template)
```yaml
TARGET_HOST: "https://your-api.com"
LOCUST_SCENARIO: "custom"
```

Template for testing your own API. Edit `locust/scenarios/custom.py`.

### Switch Scenarios

```bash
# Edit ConfigMap
kubectl edit configmap locust-config -n locust

# Update:
data:
  TARGET_HOST: "https://httpbin.org"
  LOCUST_SCENARIO: "httpbin"

# Restart pods to apply changes
kubectl rollout restart deployment/locust-master -n locust
kubectl rollout restart deployment/locust-worker -n locust
```

## Monitoring

### Kubernetes

```bash
# View pod status
kubectl get pods -n locust

# View logs
kubectl logs -f deployment/locust-master -n locust
kubectl logs -f deployment/locust-worker -n locust

# Monitor autoscaling
kubectl get hpa -n locust -w

# Resource usage
kubectl top pods -n locust
kubectl top nodes
```

### CloudWatch

```bash
# Tail cluster logs
aws logs tail /aws/eks/locust-cluster/cluster --follow --region eu-central-1

# Filter errors
aws logs filter-log-events \
  --log-group-name /aws/eks/locust-cluster/cluster \
  --filter-pattern "ERROR" \
  --region eu-central-1
```

### Locust Web UI

- **URL:** http://<LoadBalancer-IP>:8089
- **Real-time Metrics:** RPS, response times, failure rate
- **Charts:** Request distribution, response time percentiles
- **Export:** CSV and HTML reports

## Cost Management

### Monthly Cost Breakdown (24/7 Operation)

| Component | Cost |
|-----------|------|
| EKS Control Plane | $73 |
| 3x t3.medium nodes | $90 |
| 2x NAT Gateways | $65 |
| Network Load Balancer | $16 |
| CloudWatch Logs | $5-15 |
| **Total** | **~$250/month** |

### Cost Optimization

**Best Practice:** Destroy when not in use

```bash
# 2-hour load test
./scripts/deploy.sh
# ... run tests ...
./scripts/destroy.sh
# Cost: ~$0.68
```

**Alternatives:**
- Use SPOT instances: Save ~$60/month (60-70% discount on nodes)
- Use NodePort instead of LoadBalancer: Save $16/month
- Single NAT Gateway: Save $33/month (loses multi-AZ redundancy)

### Set Up Cost Alerts

1. Go to AWS Console → Billing → Billing Preferences
2. Enable "Receive Billing Alerts"
3. CloudWatch → Alarms → Create Alarm
4. Select "Billing" → "EstimatedCharges"
5. Set threshold (e.g., $50)

## Troubleshooting

### Issue: LoadBalancer Pending

**Symptoms:** External IP shows `<pending>` for >5 minutes

**Solution:**
```bash
kubectl describe svc locust-master -n locust
# Wait 2-3 minutes for AWS to provision NLB
```

### Issue: HPA Shows "unknown"

**Symptoms:** `kubectl get hpa` shows `<unknown>/70%`

**Solution:**
```bash
# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get deployment metrics-server -n kube-system
```

### Issue: Workers Can't Connect

**Symptoms:** Worker logs show "Failed to connect to master"

**Solution:**
```bash
# Check master service exists
kubectl get svc locust-master -n locust

# Test DNS from worker pod
kubectl exec -it deployment/locust-worker -n locust -- nslookup locust-master

# Check master logs
kubectl logs deployment/locust-master -n locust
```

### Issue: Docker Build Fails on M1/M2 Mac

**Symptoms:** `exec format error` when running container

**Solution:**
```bash
# Build for AMD64 explicitly
docker build --platform linux/amd64 -t locust-load-tests:latest .
```

For more troubleshooting, see [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#troubleshooting-guide).

## Production Deployment

This guide provides a development/testing setup. For production, implement:

### Security Hardening
- [ ] Private EKS API endpoint (`cluster_endpoint_public_access = false`)
- [ ] Restrict API access CIDRs to known IPs
- [ ] Enable ECR image scanning
- [ ] Use AWS Secrets Manager for credentials
- [ ] Implement Kubernetes Network Policies
- [ ] Enable Pod Security Standards (restricted)

### Operational Excellence
- [ ] Configure Terraform remote state (S3 + DynamoDB)
- [ ] Enable state locking
- [ ] Deploy Prometheus + Grafana for metrics
- [ ] Set up CloudWatch alarms
- [ ] Implement CI/CD pipeline (GitHub Actions, GitLab CI)
- [ ] Configure backup and disaster recovery
- [ ] Document incident response runbooks

### Cost Optimization
- [ ] Use SPOT instances for worker nodes
- [ ] Implement node auto-scaling (Cluster Autoscaler)
- [ ] Right-size instance types based on workload
- [ ] Use Reserved Instances for long-term deployments
- [ ] Enable AWS Cost Anomaly Detection

## Development

### Update Docker Image

```bash
# Make changes to locust scenarios
vim locust/scenarios/custom.py

# Rebuild and push
./scripts/build-and-push.sh v1.1.0

# Update deployments
kubectl set image deployment/locust-master locust=<ECR-URL>:v1.1.0 -n locust
kubectl set image deployment/locust-worker locust=<ECR-URL>:v1.1.0 -n locust
```

### Modify Infrastructure

```bash
# Edit Terraform configuration
vim terraform/variables.tf

# Plan changes
cd terraform && terraform plan

# Apply changes
terraform apply

# Update kubeconfig if cluster changed
aws eks update-kubeconfig --region eu-central-1 --name locust-cluster
```

### Test Locally

```bash
# Build Docker image
docker build -t locust-test -f docker/Dockerfile .

# Run master locally
docker run -p 8089:8089 \
  -e LOCUST_MODE=master \
  -e TARGET_HOST=https://jsonplaceholder.typicode.com \
  locust-test

# Access at http://localhost:8089
```

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Locust
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: eu-central-1
    - uses: hashicorp/setup-terraform@v2
    - name: Deploy
      run: ./scripts/deploy.sh
```

## Support

- **AWS EKS Documentation:** https://docs.aws.amazon.com/eks/
- **Locust Documentation:** https://docs.locust.io/
- **Terraform AWS Provider:** https://registry.terraform.io/providers/hashicorp/aws/
- **Kubernetes Documentation:** https://kubernetes.io/docs/

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is provided as-is for educational and testing purposes.

## Authors

Created by the SRE team as a production-ready template for distributed load testing.

---

**Version:** 1.0.0
**Last Updated:** 2025-11-08
**Terraform:** >= 1.5
**Kubernetes:** 1.28
**AWS Region:** eu-central-1 (Frankfurt)
