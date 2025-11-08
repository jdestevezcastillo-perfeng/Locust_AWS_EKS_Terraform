# Locust on AWS EKS - Complete SRE Deployment Guide

## 📋 Overview

This project provides a **production-ready, Infrastructure-as-Code (IaC) solution** for deploying distributed Locust load testing on AWS EKS (Elastic Kubernetes Service).

### What This Does

Automates the complete deployment of:

```
┌─────────────────────────────────────────────┐
│           AWS Cloud Environment              │
│ ┌─────────────────────────────────────────┐ │
│ │        EKS Kubernetes Cluster            │ │
│ │                                          │ │
│ │  ┌──────────────────┐                   │ │
│ │  │ Locust Master    │  (1 replica)      │ │
│ │  │ - Coordinator    │  Web UI: port 8089│ │
│ │  │ - Web Dashboard  │  Master: port 5557│ │
│ │  └──────────────────┘                   │ │
│ │         │ Commands                       │ │
│ │         ├─────────┬──────────┬──────────┤ │
│ │         ▼         ▼          ▼          ▼ │
│ │  ┌─────────┐┌─────────┐┌─────────┐...  │ │
│ │  │ Worker 1││ Worker 2││ Worker 3│      │ │
│ │  │ (Load)  ││ (Load)  ││ (Load)  │      │ │
│ │  └─────────┘└─────────┘└─────────┘      │ │
│ │         │    Generates Load              │ │
│ │         └────────────────────────────────┤ │
│ │                      ↓                    │ │
│ │            Target API (Any Public API)   │ │
│ │                                          │ │
│ │  Auto-scales: 3-20 workers based on CPU │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Key Features

✅ **Complete IaC**: Everything defined in code (Terraform + Kubernetes YAML)
✅ **Single Command Deployment**: `./deploy.sh` for everything
✅ **Single Command Destruction**: `./destroy.sh` for safe cleanup
✅ **Auto-Scaling**: Kubernetes HPA scales workers 3-20 based on load
✅ **Production-Ready**: Security best practices, monitoring, logging
✅ **Multi-Environment**: Dev, staging, production configurations
✅ **Well-Documented**: Comprehensive guides and inline comments
✅ **Cost-Conscious**: Easy cleanup prevents unexpected bills

---

## 🚀 Quick Start

### Prerequisites

Ensure you have installed:
- `terraform` >= 1.0
- `aws-cli` >= 2.0
- `kubectl` >= 1.28
- `docker` >= 20.0
- `jq` (JSON parser)
- AWS account with IAM permissions

### Deploy in 3 Steps

```bash
# 1. Navigate to project
cd /home/lostborion/Documents/veeam-extended

# 2. Deploy (takes 30-40 minutes)
./deploy.sh

# 3. Access Locust UI
# URL will be displayed at the end
```

That's it! Your Locust cluster is running on AWS EKS.

### Full Deployment Output

The script will:
1. ✓ Validate prerequisites
2. ✓ Create AWS infrastructure (VPC, EKS, ECR) ~20min
3. ✓ Configure kubectl to access cluster
4. ✓ Build Docker image with Locust
5. ✓ Push image to ECR
6. ✓ Deploy to Kubernetes ~3min
7. ✓ Display LoadBalancer URL to access web UI

---

## 📁 Project Structure

```
veeam-extended/
│
├── deploy.sh                           # ⭐ Single-command deployment
├── destroy.sh                          # ⭐ Single-command destruction
├── README.md                           # This file
├── .gitignore
│
├── terraform/                          # Infrastructure as Code
│   ├── main.tf                         # AWS resources (VPC, EKS, ECR)
│   ├── variables.tf                    # Configuration variables
│   ├── outputs.tf                      # Output values
│   └── terraform.tfvars                # Default values
│
├── docker/                             # Container definition
│   ├── Dockerfile                      # Multi-stage build
│   ├── entrypoint.sh                   # Container startup script
│   └── .dockerignore
│
├── kubernetes/                         # K8s manifests
│   └── base/
│       ├── namespace.yaml              # Isolated environment
│       ├── configmap.yaml              # Test configuration
│       ├── master-deployment.yaml      # Locust coordinator
│       ├── master-service.yaml         # LoadBalancer service
│       ├── worker-deployment.yaml      # Load generators
│       └── worker-hpa.yaml             # Auto-scaling config
│
├── tests/                              # Load test scenarios
│   ├── locustfile.py                   # Test entry point
│   ├── scenarios/
│   │   ├── jsonplaceholder.py          # JSONPlaceholder API tests
│   │   ├── httpbin.py                  # HTTPBin tests
│   │   └── custom.py                   # Template for custom tests
│   └── __init__.py
│
├── scripts/                            # Automation
│   ├── lib/
│   │   ├── colors.sh                   # Colored output functions
│   │   └── common.sh                   # Utility functions
│   ├── deploy/                         # Deployment phases
│   │   ├── 01-validate-prereqs.sh
│   │   ├── 02-deploy-infrastructure.sh
│   │   ├── 03-configure-kubectl.sh
│   │   ├── 04-build-push-image.sh
│   │   └── 05-deploy-kubernetes.sh
│   ├── destroy/                        # Destruction phases
│   │   ├── 01-delete-k8s-resources.sh
│   │   ├── 02-delete-ecr-images.sh
│   │   ├── 03-destroy-infrastructure.sh
│   │   └── 04-cleanup-local.sh
│   └── utils/                          # Utility scripts (monitoring, scaling, etc)
│
├── config/                             # Configuration files
│   ├── environments/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── terraform.tfvars
│
├── docs/                               # Documentation
│   ├── DEPLOYMENT_GUIDE.md
│   ├── TERRAFORM_GUIDE.md
│   ├── ARCHITECTURE.md
│   └── QUICKSTART.md
│
├── pyproject.toml                      # Python dependencies
├── poetry.lock                         # Locked versions
└── reports/                            # Test results (gitignored)
```

---

## 💻 Usage

### Deploy to Dev Environment

```bash
./deploy.sh dev
```

### Deploy to Production with Custom Tag

```bash
./deploy.sh prod v1.2.3
```

### Destroy All Resources

```bash
./destroy.sh
# You'll be asked to confirm with 'destroy' and 'yes'
```

### Access Locust Web UI

After deployment, the LoadBalancer URL will be displayed:

```
http://<EXTERNAL-IP>:8089
```

Or port-forward locally:

```bash
kubectl port-forward -n locust svc/locust-master 8089:8089
# Then open: http://localhost:8089
```

### Common Operations

**View pod status:**
```bash
kubectl get pods -n locust
```

**View logs (master):**
```bash
kubectl logs deployment/locust-master -n locust -f
```

**View logs (workers):**
```bash
kubectl logs deployment/locust-worker -n locust -f
```

**Scale workers manually:**
```bash
kubectl scale deployment locust-worker --replicas=10 -n locust
```

**Monitor auto-scaling:**
```bash
kubectl get hpa -n locust -w
```

---

## 🏗️ Architecture

### Components

**Master Node** (1 replica)
- Coordinates all workers
- Serves web dashboard (port 8089)
- Listens for worker connections (port 5557)
- Aggregates test results

**Worker Nodes** (3-20 replicas, auto-scaled)
- Run actual load tests
- Execute Locust test scenarios
- Send metrics to master
- Auto-scale based on CPU/memory usage

**Load Balancer Service**
- Exposes master web UI to external access
- AWS LoadBalancer (hostname/IP auto-assigned)

**Horizontal Pod Autoscaler (HPA)**
- Scales workers automatically
- Trigger: CPU > 70% or Memory > 80%
- Min replicas: 3, Max replicas: 20

### Infrastructure

**AWS Resources Created:**
- VPC with public and private subnets
- EKS Cluster (managed Kubernetes)
- Auto-scaling node group (t3.medium instances)
- EC2 NAT Gateways (for secure egress)
- ECR Repository (private Docker registry)
- CloudWatch Logs (for auditing and debugging)
- IAM roles and security groups

**Region:** eu-central-1 (Frankfurt)

---

## 📊 Cost Estimation

| Component | Cost/Hour | Cost/Day | Cost/Month |
|-----------|-----------|----------|-----------|
| EKS Control Plane | $0.10 | $2.40 | $73 |
| 3x t3.medium nodes | $0.125 | $3.00 | $90 |
| 2x NAT Gateways | $0.09 | $2.16 | $65 |
| LoadBalancer | $0.023 | $0.55 | $16 |
| CloudWatch Logs | $0.007 | $0.17 | $5 |
| **TOTAL** | **$0.34** | **$8.28** | **$249** |

### Cost Optimization

**Option 1: Use Spot Instances (saves 60-70%)**
```bash
# Edit terraform/terraform.tfvars
capacity_type = "SPOT"
```

**Option 2: Single NAT Gateway (saves $33/month)**
```bash
# Edit terraform/main.tf
single_nat_gateway = true
```

**Option 3: NodePort Service (saves $16/month)**
Replace LoadBalancer with NodePort in kubernetes/base/master-service.yaml

**Recommendation:** Delete cluster when not in use
```bash
./destroy.sh  # Takes ~15 minutes, saves all future costs
```

---

## 🔐 Security

This solution implements:

✓ **Private subnets** for worker nodes (no public IPs)
✓ **Security groups** with least-privilege access
✓ **Non-root containers** (UID 1000)
✓ **Multi-stage Docker builds** (smaller attack surface)
✓ **IAM least-privilege roles** (only required permissions)
✓ **CloudWatch audit logging** (track all changes)
✓ **Encrypted communication** (HTTPS/TLS)

### Additional Hardening (Future)

- AWS Secrets Manager for credentials
- Pod Network Policies (restrict inter-pod traffic)
- RBAC (Role-Based Access Control)
- Private EKS endpoint
- VPC Flow Logs

---

## 📚 Documentation

- **[QUICKSTART.md](docs/QUICKSTART.md)** - Quick reference for common tasks
- **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** - Complete deployment walkthrough
- **[TERRAFORM_GUIDE.md](docs/TERRAFORM_GUIDE.md)** - Terraform-specific details
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System architecture and design
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions

---

## 🧪 Testing

The project includes multiple test scenarios:

### JSONPlaceholder (Default)
Tests against free public API (https://jsonplaceholder.typicode.com)

- `GET /posts` - List posts
- `GET /posts/{id}` - Get specific post
- `POST /posts` - Create post
- `PUT /posts/{id}` - Update post
- `DELETE /posts/{id}` - Delete post

### HTTPBin
Tests HTTP functionality (https://httpbin.org)

- GET/POST/PUT/DELETE requests
- Headers and authentication
- Data compression
- Cookies and redirects

### Custom Tests
Template for adding your own API tests:

```python
# tests/scenarios/my_api.py
from locust import HttpUser, task, between

class MyAPIUser(HttpUser):
    wait_time = between(1, 3)

    @task
    def my_task(self):
        self.client.get("/api/endpoint")
```

Then set environment variable:
```bash
export SCENARIO=my_api
./deploy.sh
```

---

## 🔄 Lifecycle

### Initial Deployment

```bash
./deploy.sh dev          # Deploy development environment
# ~40 minutes total
```

### Running Tests

1. Access Locust UI: `http://<LoadBalancer-IP>:8089`
2. Click "New Test Run"
3. Configure:
   - Number of users
   - Spawn rate
   - Run time
4. Click "Start"
5. Monitor results in dashboard

### Monitoring

**In Locust UI:**
- Real-time request/response metrics
- Success/failure rates
- Response time percentiles
- Charts and graphs

**Via kubectl:**
```bash
kubectl top pods -n locust      # CPU/Memory usage
kubectl get hpa -n locust       # Auto-scaler metrics
kubectl logs -f ...             # Live logs
```

**Via AWS Console:**
- CloudWatch logs
- EKS cluster metrics
- EC2 instance metrics

### Cleanup

```bash
./destroy.sh             # Destroy all resources
# ~15-20 minutes
```

---

## 🐛 Troubleshooting

### Deployment Hangs
- Check logs: `kubectl logs deployment/locust-master -n locust`
- Verify node status: `kubectl get nodes`
- Check auto-scaling: `kubectl get hpa -n locust`

### Can't Access Locust UI
- LoadBalancer IP may take 2-3 minutes to assign
- Check: `kubectl get svc locust-master -n locust`
- Use port-forward: `kubectl port-forward -n locust svc/locust-master 8089:8089`

### Workers Won't Connect
- Check master logs: `kubectl logs deployment/locust-master -n locust`
- Verify service is running: `kubectl get svc locust-master -n locust`
- Check pod network: `kubectl get pods -n locust -o wide`

### Out of Memory
- Increase memory limits in kubernetes/base/worker-deployment.yaml
- Reduce number of users per pod
- Increase number of worker replicas

### Costs Higher Than Expected
- Delete/destroy cluster when not in use
- Check EKS CloudWatch logs for errors
- Review AWS billing dashboard

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more help.

---

## 🤝 Contributing

This is an SRE-focused project. Contributions welcome for:
- Terraform module improvements
- Additional test scenarios
- Kubernetes optimizations
- Documentation updates
- Bug fixes

---

## 📄 License

This project is provided as-is for educational and development purposes.

---

## 📞 Support

For issues:
1. Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. Review logs: `kubectl logs -f deployment/locust-master -n locust`
3. Check AWS console for infrastructure issues
4. Verify AWS credentials: `aws sts get-caller-identity`

---

## 🎯 Next Steps

1. **Review Architecture**: Read [ARCHITECTURE.md](docs/ARCHITECTURE.md)
2. **Deploy**: Run `./deploy.sh dev`
3. **Run Test**: Access UI and start load test
4. **Monitor**: Watch metrics in dashboard
5. **Iterate**: Adjust load parameters and run again
6. **Cleanup**: Run `./destroy.sh`

Happy load testing! 🚀
