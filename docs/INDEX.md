# Documentation Index

Complete guide to deploying distributed Locust load testing on AWS EKS.

## Quick Navigation

### Getting Started (Read First)

1. **[QUICKSTART.md](QUICKSTART.md)** - Start here for rapid deployment
   - Prerequisites checklist
   - One-command deployment
   - Basic operations
   - 5-10 minute read

2. **[README_SRE.md](README_SRE.md)** - Project overview
   - Architecture diagram
   - Feature highlights
   - Quick reference commands
   - 15-20 minute read

### Comprehensive Guides

3. **[SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md)** - Complete SRE handbook
   - Detailed architecture decisions (WHY, not just HOW)
   - Phase-by-phase deployment walkthrough
   - Production considerations
   - Troubleshooting guide
   - Cost analysis and optimization
   - 60+ pages, 2-3 hour read

4. **[DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)** - File inventory
   - Complete file-by-file breakdown
   - Resource specifications
   - Validation checklists
   - Production hardening guide
   - 30-45 minute read

## Documentation by Audience

### For DevOps/SRE Engineers
**Goal:** Understand architecture and deploy infrastructure

1. Read [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md) sections:
   - Architecture Design Decisions
   - Phase 1: Infrastructure Setup
   - Monitoring and Verification
   - Production Considerations

2. Review Terraform files:
   - `/home/lostborion/Documents/veeam/terraform/main.tf`
   - `/home/lostborion/Documents/veeam/terraform/variables.tf`

3. Run deployment:
   ```bash
   ./scripts/deploy.sh
   ```

### For Performance Engineers
**Goal:** Create and run load tests

1. Read [QUICKSTART.md](QUICKSTART.md)
2. Review test scenarios:
   - `/home/lostborion/Documents/veeam/locust/scenarios/jsonplaceholder.py`
   - `/home/lostborion/Documents/veeam/locust/scenarios/httpbin.py`
3. Customize for your API:
   - Edit `/home/lostborion/Documents/veeam/locust/scenarios/custom.py`
   - Update `/home/lostborion/Documents/veeam/kubernetes/configmap.yaml`

### For Team Leads/Architects
**Goal:** Evaluate solution and cost

1. Read [README_SRE.md](README_SRE.md) - Architecture overview
2. Review [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - Cost breakdown
3. Check security checklist in [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#production-considerations)

### For Platform Engineers
**Goal:** Integrate into CI/CD pipeline

1. Read [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md) section:
   - CI/CD Integration
2. Review automation scripts:
   - `/home/lostborion/Documents/veeam/scripts/deploy.sh`
   - `/home/lostborion/Documents/veeam/scripts/destroy.sh`
3. Configure GitHub Actions/GitLab CI workflow

## Documentation by Task

### First-Time Deployment
1. [QUICKSTART.md](QUICKSTART.md) - Prerequisites
2. [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md) - Phase 1-4
3. Run: `./scripts/deploy.sh`
4. Verify: `./scripts/verify-deployment.sh`

### Running Load Tests
1. Access Locust UI: `kubectl get svc locust-master -n locust`
2. Configure test parameters (users, spawn rate, duration)
3. Start test and monitor metrics
4. Export results (CSV/HTML)

### Switching Test Scenarios
1. [QUICKSTART.md](QUICKSTART.md#change-test-target)
2. Edit ConfigMap: `kubectl edit configmap locust-config -n locust`
3. Restart pods: `kubectl rollout restart deployment -n locust`

### Troubleshooting Issues
1. [QUICKSTART.md](QUICKSTART.md#troubleshooting) - Common issues
2. [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#troubleshooting-guide) - Detailed solutions
3. Run: `./scripts/verify-deployment.sh`

### Cost Management
1. [README_SRE.md](README_SRE.md#cost-management) - Cost breakdown
2. [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#cost-management-and-cleanup) - Optimization strategies
3. Run: `./scripts/destroy.sh` when finished

### Production Deployment
1. [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#production-considerations) - Hardening checklist
2. [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md#production-hardening-checklist) - Validation steps
3. Review security and operational best practices

## File Locations Quick Reference

### Infrastructure
```
/home/lostborion/Documents/veeam/terraform/
├── main.tf              # VPC, EKS, ECR, CloudWatch
├── variables.tf         # Configuration parameters
├── outputs.tf           # Export values
└── terraform.tfvars     # Environment settings
```

### Docker
```
/home/lostborion/Documents/veeam/docker/
├── Dockerfile           # Multi-stage build
├── entrypoint.sh        # Master/worker startup
└── .dockerignore        # Build optimization
```

### Kubernetes
```
/home/lostborion/Documents/veeam/kubernetes/
├── namespace.yaml
├── configmap.yaml       # Test configuration
├── master-deployment.yaml
├── master-service.yaml
├── worker-deployment.yaml
└── worker-hpa.yaml      # Auto-scaling
```

### Test Scenarios
```
/home/lostborion/Documents/veeam/locust/
├── locustfile.py        # Scenario loader
└── scenarios/
    ├── jsonplaceholder.py
    ├── httpbin.py
    └── custom.py        # Your custom tests
```

### Automation
```
/home/lostborion/Documents/veeam/scripts/
├── deploy.sh            # Full deployment
├── destroy.sh           # Cleanup
├── build-and-push.sh    # Docker build
└── verify-deployment.sh # Health checks
```

## Common Commands

### Deployment
```bash
# Full deployment
./scripts/deploy.sh

# Verify deployment
./scripts/verify-deployment.sh

# Destroy everything
./scripts/destroy.sh
```

### Monitoring
```bash
# Pod status
kubectl get pods -n locust

# Logs
kubectl logs -f deployment/locust-master -n locust

# Auto-scaling status
kubectl get hpa -n locust -w

# Resource usage
kubectl top pods -n locust
```

### Configuration
```bash
# Edit test configuration
kubectl edit configmap locust-config -n locust

# Update Docker image
./scripts/build-and-push.sh v1.2.0

# Apply new image
kubectl set image deployment/locust-worker locust=<ECR-URL>:v1.2.0 -n locust
```

## Key Metrics

- **Deployment Time:** 25-30 minutes
- **Destruction Time:** 8-12 minutes
- **Cost per Hour:** ~$0.34
- **Cost per Month (24/7):** ~$250
- **Cost per Test (2hr):** ~$0.68
- **Auto-Scaling:** 3-20 worker pods
- **Node Scaling:** 3-10 EC2 instances

## Support Resources

- **AWS EKS:** https://docs.aws.amazon.com/eks/
- **Locust:** https://docs.locust.io/
- **Terraform:** https://registry.terraform.io/providers/hashicorp/aws/
- **Kubernetes:** https://kubernetes.io/docs/

## Version Information

- **Project Version:** 1.0.0
- **Terraform:** >= 1.5
- **Kubernetes:** 1.28
- **Python:** 3.10+
- **Locust:** >= 2.42.2
- **AWS Region:** eu-central-1 (Frankfurt)
- **Last Updated:** 2025-11-08

## Quick Decision Tree

**I want to...**

- **Deploy quickly** → [QUICKSTART.md](QUICKSTART.md)
- **Understand architecture** → [README_SRE.md](README_SRE.md)
- **Learn design decisions** → [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#architecture-design-decisions)
- **Fix an issue** → [QUICKSTART.md](QUICKSTART.md#troubleshooting) or [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#troubleshooting-guide)
- **Estimate costs** → [README_SRE.md](README_SRE.md#cost-management)
- **Prepare for production** → [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md#production-considerations)
- **See all files** → [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)
- **Customize tests** → `/home/lostborion/Documents/veeam/locust/scenarios/custom.py`

---

**Start Here:** [QUICKSTART.md](QUICKSTART.md) for rapid deployment, then dive into [SRE_DEPLOYMENT_GUIDE.md](SRE_DEPLOYMENT_GUIDE.md) for comprehensive understanding.
