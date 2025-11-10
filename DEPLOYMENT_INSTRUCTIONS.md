# Complete SRE Deployment Instructions

## 📖 Welcome to the Comprehensive Locust on AWS EKS Deployment Guide

This document walks an SRE engineer through the complete process of deploying a production-ready, auto-scaling Locust load testing environment on AWS EKS using Infrastructure-as-Code (Terraform) and Kubernetes.

---

## 🎯 What You'll Learn

After completing this guide, you will have:

1. ✅ Created a complete AWS infrastructure (VPC, EKS cluster, ECR)
2. ✅ Built a Docker image with Locust and Poetry-managed dependencies
3. ✅ Deployed distributed Locust to Kubernetes with master-worker architecture
4. ✅ Configured auto-scaling for elastic load generation
5. ✅ Set up monitoring and logging
6. ✅ Learned how to scale up/down and manage the cluster
7. ✅ Understood how to cleanly destroy all resources

---

## 📋 Prerequisites Checklist

Before starting, verify you have:

- [ ] **AWS Account** with sufficient credits/budget (~$250/month for 24/7 or $0.68 for 2-hour test)
- [ ] **AWS CLI** v2 installed and configured:
  ```bash
  aws --version
  aws sts get-caller-identity  # Verify credentials work
  ```
- [ ] **Terraform** >= 1.0 installed:
  ```bash
  terraform --version
  ```
- [ ] **kubectl** >= 1.28 installed:
  ```bash
  kubectl version --client
  ```
- [ ] **Docker** installed and running:
  ```bash
  docker ps  # Verify daemon is running
  ```
- [ ] **jq** JSON processor:
  ```bash
  which jq  # Should return /usr/bin/jq or similar
  ```

### Install Missing Prerequisites

**macOS:**
```bash
brew install terraform awscli kubectl docker jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y terraform awscli kubectl jq
# For Docker, see: https://docs.docker.com/engine/install/ubuntu/
```

**Verify All Prerequisites:**
```bash
terraform --version && aws --version && kubectl version --client && docker ps && which jq
```

---

## 🚀 Step-by-Step Deployment

### Step 1: Navigate to Project Directory

```bash
cd /home/lostborion/Documents/veeam-extended
```

Verify you see:
```
deploy.sh                    # Main deployment script
destroy.sh                   # Cleanup script
README.md                    # Project documentation
terraform/                   # Infrastructure as Code
docker/                      # Container definition
kubernetes/                  # Kubernetes manifests
tests/                       # Locust test scenarios
scripts/                     # Automation scripts
```

### Step 2: Review the Deployment Plan (Optional but Recommended)

The deployment consists of 5 phases. Review what will happen:

```bash
# Just for information - shows what will be created
cat deploy.sh | grep "Phase"
```

Expected phases:
1. Validate Prerequisites (2-3 min)
2. Deploy AWS Infrastructure (18-22 min) - **Creates VPC, EKS, ECR**
3. Configure kubectl (2-5 min) - **Connects to cluster**
4. Build & Push Docker Image (3-5 min) - **Builds container**
5. Deploy to Kubernetes (2-3 min) - **Deploys Locust**

**Total Time: 30-40 minutes**

### Step 3: Start Deployment

**For Development (First-Time):**
```bash
./deploy.sh dev
```

**For Production:**
```bash
./deploy.sh prod
```

**With Custom Docker Image Tag:**
```bash
./deploy.sh dev v1.2.3
```

### Step 4: Monitor Deployment Progress

The script will output colored status messages. Watch for:

```
✓ Success messages (green)
ℹ Information messages (blue)
⚠ Warnings (yellow)
✗ Errors (red)
```

During this phase you will be prompted to:
- Choose the AWS region from a curated list
- Enter comma-separated CIDR blocks allowed to reach the EKS API server (0.0.0.0/0 is rejected unless `ALLOW_INSECURE_ENDPOINT=true`)

### Step 5: Wait for LoadBalancer IP

Near the end, you'll see:

```
Locust Web UI available at:
  http://123.45.67.89:8089
```

If you see "pending", wait 1-2 more minutes and check:

```bash
kubectl get svc locust-master -n locust
```

### Step 6: Access Locust Web UI

Open the URL in your browser:
```
http://<EXTERNAL-IP>:8089
```

You should see the Locust dashboard with:
- Start/Stop test buttons
- User configuration fields
- Real-time statistics

---

## 💼 Understanding the Deployment

### What Gets Created

#### AWS Resources (via Terraform)

| Resource | Purpose | Cost/Month |
|----------|---------|-----------|
| EKS Cluster | Managed Kubernetes | $73 |
| 3 EC2 t3.medium nodes | Worker nodes | $90 |
| VPC, Subnets, NAT | Networking | ~$65 |
| ECR Repository | Docker registry | <$5 |
| LoadBalancer | External access | $16 |
| CloudWatch Logs | Logging | ~$5 |
| **Total** | | ~$249 |

#### Kubernetes Resources (via kubectl)

| Resource | Replicas | Purpose |
|----------|----------|---------|
| Locust Master | 1 | Coordinates workers |
| Locust Workers | 3-20 (auto-scaling) | Generate load |
| LoadBalancer Service | 1 | External access |
| HPA | 1 | Auto-scaling rules |
| ConfigMap | 1 | Test configuration |

#### Docker Image

- Based on Python 3.10
- Includes Locust framework
- Includes Prometheus metrics exporter
- Includes multiple test scenarios

### How It Works

```
1. You start test in web UI
                ↓
2. Master receives request
                ↓
3. Master sends "spawn user" commands to workers
                ↓
4. Workers execute test scenarios (requests)
                ↓
5. Workers send metrics back to master
                ↓
6. Master aggregates and displays in web UI
                ↓
7. When target load reached, test sustains
                ↓
8. If CPU/Memory high, HPA adds more workers
                ↓
9. When test stops, workers shut down gracefully
```

### Architecture Diagram

```
                    You (Browser)
                         │
                         │ HTTP
                         ▼
                   ┌──────────────┐
                   │  LoadBalancer│
                   │  (AWS ELB)   │
                   └──────┬───────┘
                          │
            ┌─────────────┼─────────────┐
            │             │             │
            ▼             ▼             ▼
        ┌────────┐   ┌────────┐   ┌────────┐
        │ Master │   │ Worker1│   │ Worker2│  ... Worker N
        │ Pod    │   │ Pod    │   │ Pod    │
        └────┬───┘   └───┬────┘   └───┬────┘
             │           │            │
             └───────────┼────────────┘
                         │
              Kubernetes Cluster
             (Inside Private Subnets)
```

---

## 🎮 Running Your First Test

### 1. Access Locust UI

```
http://<LoadBalancer-IP>:8089
```

### 2. Configure Test Parameters

- **Number of users**: Start with 10 (default is 100)
- **Spawn rate**: Users per second (default is 10 → 10 seconds to full load)
- **Run time**: How long to run (default is infinite - stop manually)

### 3. Select Test Scenario

By default, targets: https://jsonplaceholder.typicode.com

Available scenarios:
- `/posts` - List API
- `/posts/{id}` - Single resource API
- `/posts` (POST) - Create API
- `/posts/{id}` (PUT) - Update API
- `/posts/{id}` (DELETE) - Delete API

### 4. Click "Start"

Watch the dashboard as traffic increases:
- RPS (Requests Per Second) graph
- Response time graph
- Success/Failure rates
- Detailed statistics by endpoint

### 5. Monitor Auto-Scaling

While test is running, check:
```bash
kubectl get hpa -n locust -w
# Watch worker count increase as load increases
```

### 6. Stop Test

Click "Stop" in web UI when done.

---

## 📊 Monitoring & Observability

### Option 1: Kubernetes Dashboard (kubectl)

```bash
# View all pods
kubectl get pods -n locust

# View pod resources
kubectl top pods -n locust

# View HPA status
kubectl get hpa -n locust

# Watch HPA scaling in real-time
kubectl get hpa -n locust -w
```

### Option 2: Logs

```bash
# Master logs
kubectl logs deployment/locust-master -n locust -f

# Worker logs
kubectl logs deployment/locust-worker -n locust -f

# Specific pod logs
kubectl logs <pod-name> -n locust -f
```

### Option 3: AWS CloudWatch

```bash
# View logs in CloudWatch
aws logs tail /aws/eks/locust-cluster --follow
```

### Option 4: Locust Web UI

Built-in metrics:
- Total RPS (requests per second)
- Response times (min, avg, max, median, 95th%, 99th%)
- Success and failure rates
- Failures by error type

---

## ⚙️ Common Operations

### Scale Workers (Manual)

```bash
# Scale to 10 workers
kubectl scale deployment locust-worker --replicas=10 -n locust

# Verify
kubectl get pods -n locust | grep worker
```

### Restart Master

```bash
kubectl rollout restart deployment/locust-master -n locust
kubectl rollout status deployment/locust-master -n locust
```

### Update Test Scenario

```bash
# Edit and rebuild Docker image
docker build -f docker/Dockerfile -t locust-load-tests:v2 .
docker tag locust-load-tests:v2 <ECR-URL>:v2
docker push <ECR-URL>:v2

# Update Kubernetes to use new image
kubectl set image deployment/locust-master locust=<ECR-URL>:v2 -n locust
kubectl set image deployment/locust-worker locust=<ECR-URL>:v2 -n locust
```

### View Resource Usage

```bash
# Top nodes
kubectl top nodes

# Top pods
kubectl top pods -n locust

# Detailed pod info
kubectl describe pod <pod-name> -n locust
```

### Get LoadBalancer Details

```bash
kubectl get svc locust-master -n locust -o wide
```

Output shows:
- External IP/Hostname
- Internal IP
- Ports
- Age

---

## 🧹 Cleanup & Destruction

### Option 1: Interactive Destruction (Recommended)

```bash
./destroy.sh
```

The script will:
1. Ask for confirmation ("Type 'destroy'")
2. Ask to confirm again ("Type 'yes'")
3. Delete Kubernetes resources (~2 min)
4. Delete ECR images
5. Destroy AWS infrastructure (~15 min)
6. Clean up local files

### Option 2: Manual Step-by-Step

If automated script fails:

```bash
# 1. Delete Kubernetes namespace (all resources)
kubectl delete namespace locust

# 2. Delete Docker images from ECR
aws ecr list-images --repository-name locust-load-tests --region eu-central-1
aws ecr batch-delete-image --repository-name locust-load-tests --image-ids imageTag=latest

# 3. Destroy Terraform infrastructure
cd terraform
terraform destroy

# 4. Clean up local state
rm -rf terraform/.terraform terraform.tfstate*
rm -f .env.deployment
```

### Verify Cleanup

```bash
# Should be empty
kubectl get pods -n locust  # Error: namespace not found (expected)

# Should show ~$0
aws ec2 describe-instances | grep -i running  # No EKS nodes

# Check AWS console to verify resources deleted
```

---

## 🐛 Troubleshooting

### Issue: "AWS credentials not configured"

**Solution:**
```bash
aws configure
# Enter: AWS Access Key ID
# Enter: AWS Secret Access Key
# Enter: Default region (eu-central-1)
# Enter: Default output format (json)

# Verify
aws sts get-caller-identity
```

### Issue: Terraform plan/apply fails

**Solutions:**
```bash
# Validate configuration
cd terraform
terraform validate

# Check for syntax errors
terraform fmt -check

# Increase terraform logging
export TF_LOG=DEBUG
terraform plan
```

### Issue: Kubectl can't connect to cluster

**Solutions:**
```bash
# Reconfigure
aws eks update-kubeconfig --name locust-cluster --region eu-central-1

# Verify
kubectl cluster-info
kubectl auth can-i get pods --all-namespaces
```

### Issue: Docker build fails

**Solutions:**
```bash
# Check Docker daemon
docker ps

# Check Docker disk space
docker system df

# Check Dockerfile syntax
docker build -f docker/Dockerfile --no-cache .

# Check logs
docker build -f docker/Dockerfile . 2>&1 | tail -50
```

### Issue: LoadBalancer IP not assigned

**Normal behavior:** Takes 2-3 minutes
```bash
# Check status
kubectl get svc locust-master -n locust

# Wait for EXTERNAL-IP to populate
# If still pending after 5 minutes:
kubectl describe svc locust-master -n locust
```

### Issue: Pods in CrashLoopBackOff

**Solutions:**
```bash
# Check logs
kubectl logs <pod-name> -n locust

# Check events
kubectl describe pod <pod-name> -n locust

# Common causes:
# - Image pull error
# - Resource limits exceeded
# - Liveness probe failing

# Force restart
kubectl delete pod <pod-name> -n locust
```

### Issue: Running out of memory

**Solutions:**
```bash
# Check current usage
kubectl top pods -n locust

# Increase memory limit
# Edit kubernetes/base/worker-deployment.yaml
# Change memory limits and redeploy

# Or scale to more workers (distribute load)
kubectl scale deployment locust-worker --replicas=10 -n locust
```

---

## 💡 Advanced Topics

### Using Different Test Scenarios

The project includes multiple test scenarios. To use a different one:

```bash
# In Kubernetes manifest, set environment variable:
# kubernetes/base/master-deployment.yaml
# kubernetes/base/worker-deployment.yaml

env:
  - name: SCENARIO
    value: "httpbin"  # Instead of jsonplaceholder

# Then redeploy
kubectl apply -f kubernetes/base/
```

Available scenarios:
- `jsonplaceholder` (default)
- `httpbin`
- `custom` (template for your own)

### Adding Custom Tests

1. Create test file in `tests/scenarios/my_api.py`
2. Import in `tests/locustfile.py`
3. Set environment variable `SCENARIO=my_api`
4. Rebuild and redeploy

### Environment-Specific Configurations

```bash
# Dev (minimal resources)
./deploy.sh dev

# Staging (realistic load)
./deploy.sh staging

# Production (high availability)
./deploy.sh prod
```

Each environment has different resource allocations in `config/environments/*/terraform.tfvars`

### Cost Optimization

**Option 1: Spot Instances (Save 60%)**
```bash
# Edit terraform/terraform.tfvars
capacity_type = "SPOT"
# Rebuild cluster
```

**Option 2: Smaller Instances**
```bash
# Edit terraform/terraform.tfvars
node_type = "t3.small"  # Instead of t3.medium
```

**Option 3: Single NAT (Save $33/month)**
```bash
# Edit terraform/main.tf
# Remove one NAT Gateway
```

---

## 📚 Further Learning

### Terraform
- Official docs: https://www.terraform.io/docs
- AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest
- EKS Module: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws

### Kubernetes
- Official docs: https://kubernetes.io/docs
- Kubectl cheat sheet: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- HPA deep dive: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

### Locust
- Official docs: https://docs.locust.io
- Best practices: https://docs.locust.io/en/stable/best-practices.html
- Advanced features: https://docs.locust.io/en/stable/advanced-features.html

### AWS
- EKS docs: https://docs.aws.amazon.com/eks/
- CloudWatch: https://docs.aws.amazon.com/cloudwatch/
- ECR: https://docs.aws.amazon.com/ecr/

---

## ✅ Checklist: Your First Deployment

- [ ] Install all prerequisites
- [ ] Navigate to `/home/lostborion/Documents/veeam-extended`
- [ ] Review infrastructure costs
- [ ] Run `./deploy.sh dev`
- [ ] Wait for LoadBalancer IP
- [ ] Access Locust web UI
- [ ] Run a test
- [ ] Monitor pods and HPA
- [ ] Check costs in AWS console
- [ ] Stop test
- [ ] Run `./destroy.sh`
- [ ] Verify all resources deleted

---

## 🎓 Learning Outcomes

After completing this guide, you should understand:

1. **Infrastructure as Code (IaC)**
   - How to define cloud infrastructure in Terraform
   - Module composition and reusability
   - State management

2. **Kubernetes**
   - Deployments and replicas
   - Services and load balancing
   - Horizontal Pod Autoscaling (HPA)
   - ConfigMaps and configuration management
   - Resource requests and limits

3. **Containerization**
   - Multi-stage Docker builds
   - Image optimization
   - Container registries (ECR)

4. **Load Testing**
   - Distributed load testing architecture
   - Master-worker patterns
   - Realistic load patterns and ramp-up

5. **DevOps/SRE Practices**
   - Automation and orchestration
   - Infrastructure as Code
   - Monitoring and observability
   - Cost management
   - Graceful shutdown and cleanup

---

## 🚀 You're Ready!

You now have a production-ready, auto-scaling, Infrastructure-as-Code solution for distributed load testing. Happy testing!

If you encounter issues:
1. Check logs: `kubectl logs deployment/locust-master -n locust`
2. Review AWS CloudWatch
3. See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## 📞 Need Help?

- Check the documentation in `docs/` folder
- Review inline script comments
- Check Terraform/Kubernetes manifests for details
- Review official documentation links above
