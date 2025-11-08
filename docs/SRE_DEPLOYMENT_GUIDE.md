# Comprehensive SRE Guide: Distributed Locust Load Testing on AWS EKS

## Table of Contents
1. [Overview](#overview)
2. [Architecture Design Decisions](#architecture-design-decisions)
3. [Prerequisites](#prerequisites)
4. [Project Structure](#project-structure)
5. [Phase 1: Infrastructure Setup with Terraform](#phase-1-infrastructure-setup-with-terraform)
6. [Phase 2: Docker Image Build and Registry](#phase-2-docker-image-build-and-registry)
7. [Phase 3: Kubernetes Deployment](#phase-3-kubernetes-deployment)
8. [Phase 4: Deployment Execution](#phase-4-deployment-execution)
9. [Monitoring and Verification](#monitoring-and-verification)
10. [Cost Management and Cleanup](#cost-management-and-cleanup)
11. [Troubleshooting Guide](#troubleshooting-guide)
12. [Production Considerations](#production-considerations)

---

## Overview

This guide provides a complete, production-ready solution for deploying a distributed Locust load testing infrastructure on AWS EKS. The architecture supports horizontal auto-scaling, centralized monitoring, and complete infrastructure-as-code management.

**What This Guide Delivers:**
- Fully automated AWS infrastructure provisioning via Terraform
- Multi-zone, highly available EKS cluster in eu-central-1 (Frankfurt)
- Auto-scaling Locust workers (3-20 replicas based on CPU/memory)
- Container registry (ECR) for versioned Docker images
- CloudWatch logging and metrics collection
- Single-command deployment and destruction
- Multiple test scenarios switchable via environment variables

**Time to Deploy:** ~20-25 minutes (infrastructure provisioning takes most of this time)

**Estimated Monthly Cost:**
- Base infrastructure: ~$150-200/month (EKS cluster + t3.medium nodes)
- During load tests: Additional ~$10-30 depending on scale and duration
- **WARNING:** This is a development/testing setup. Always destroy resources when not in use.

---

## Architecture Design Decisions

### Why This Architecture?

#### 1. **Dual Subnet Design (Public + Private)**
**Decision:** Use both public and private subnets across multiple availability zones.

**Why:**
- **Public Subnets:** Host NAT Gateways and load balancers for external access
- **Private Subnets:** Host EKS worker nodes for security isolation
- **Multi-AZ:** Provides fault tolerance; if one AZ fails, workloads continue in the other
- **Security:** Worker nodes never get public IPs, reducing attack surface

**Trade-offs:**
- Increased complexity vs. all-public setup
- NAT Gateway adds ~$32/month per AZ, but necessary for production-like environment
- Alternative: All-public subnets would save costs but expose nodes directly to internet

#### 2. **EKS vs. EC2-Based Kubernetes**
**Decision:** Use managed EKS cluster instead of self-hosted Kubernetes.

**Why:**
- **Control Plane Management:** AWS handles master node upgrades, backups, and high availability
- **Security Patches:** Automatic security updates for control plane
- **Integration:** Native integration with IAM, VPC, and CloudWatch
- **Time to Value:** Focus on workloads, not cluster maintenance

**Trade-offs:**
- Higher cost (~$73/month for control plane) vs. self-managed
- Less control over control plane configuration
- For this use case: Cost is justified by reduced operational overhead

#### 3. **T3.medium Instance Type**
**Decision:** Use t3.medium (2 vCPU, 4 GB RAM) for worker nodes.

**Why:**
- **Burstable Performance:** T3 provides baseline + burst credits, ideal for variable load testing workloads
- **Cost Efficiency:** ~$0.0416/hour (~$30/month per node) vs. C5 compute-optimized at ~$68/month
- **Right-Sizing:** Each Locust worker uses ~200-500 MB RAM; 4 GB supports 6-8 workers comfortably
- **Locust Workload Pattern:** CPU-intensive during high RPS; T3 burst credits handle spikes

**Trade-offs:**
- If running 24/7 at high CPU, burst credits deplete; consider C5 instances
- For periodic load tests (typical use case), T3 is optimal

#### 4. **Horizontal Pod Autoscaler (HPA) Strategy**
**Decision:** Auto-scale Locust workers based on 70% CPU and 80% memory thresholds.

**Why:**
- **70% CPU Threshold:** Provides headroom for request spikes while maximizing utilization
- **80% Memory Threshold:** Prevents OOM kills while allowing efficient packing
- **Dual Metrics:** CPU scales for compute-intensive scenarios; memory scales for large response payloads
- **Min 3 / Max 20 Workers:** Ensures baseline capacity while capping costs

**Trade-offs:**
- Lower thresholds (e.g., 50%) would scale faster but increase costs
- Higher thresholds (e.g., 90%) save costs but risk performance degradation
- 70/80 is industry best practice for load generation workloads

#### 5. **ECR vs. Docker Hub**
**Decision:** Use AWS ECR for private image registry.

**Why:**
- **Security:** Images remain private; no public exposure of test configurations
- **Integration:** IAM-based authentication; EKS nodes pull without credentials
- **Performance:** Images stored in same region as EKS (eu-central-1) for fast pulls
- **Versioning:** Tag-based image versioning supports rollback and A/B testing

**Trade-offs:**
- ~$0.10/GB storage vs. free Docker Hub public repos
- For production use cases, private registry is non-negotiable

#### 6. **CloudWatch Logging Strategy**
**Decision:** Enable all 5 EKS control plane log types + container logs via FluentBit.

**Why:**
- **Audit Trail:** API calls, authentication attempts tracked for compliance
- **Debugging:** Controller Manager logs reveal scheduling issues
- **Security:** Authenticator logs show unauthorized access attempts
- **Retention:** 7-day retention balances cost vs. troubleshooting needs

**Trade-offs:**
- ~$0.50/GB ingestion + $0.03/GB storage
- For short-term testing, can disable scheduler/controller logs to save ~40% costs
- **Recommendation:** Keep enabled until infrastructure is stable, then tune

#### 7. **Master-Worker Locust Architecture**
**Decision:** Deploy 1 master (coordinator) + 3-20 workers (load generators).

**Why:**
- **Master:** Aggregates metrics, serves web UI, orchestrates test lifecycle
- **Workers:** Execute actual HTTP requests; horizontally scalable
- **Separation of Concerns:** Master doesn't generate load, ensuring accurate metrics
- **Web UI Access:** Single master provides unified dashboard for all workers

**Trade-offs:**
- Master becomes single point of failure (acceptable for testing infrastructure)
- Alternative: Standalone mode (no master) can't aggregate multi-node metrics

#### 8. **ConfigMap for Test Configuration**
**Decision:** Externalize target URLs and parameters in Kubernetes ConfigMap.

**Why:**
- **Immutable Images:** Same Docker image tests multiple environments (dev/staging/prod)
- **Easy Updates:** Change test targets without rebuilding images
- **Version Control:** ConfigMaps are declarative, stored in Git
- **Security:** Sensitive data (API keys) can be moved to Secrets

**Trade-offs:**
- Additional Kubernetes resource to manage vs. hardcoded values
- For enterprise use: ConfigMaps are essential for environment portability

---

## Prerequisites

### Required Tools and Access

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| **AWS CLI** | 2.x | Interact with AWS services | `brew install awscli` or [AWS Docs](https://aws.amazon.com/cli/) |
| **Terraform** | >= 1.5 | Infrastructure provisioning | `brew install terraform` or [Terraform Docs](https://terraform.io) |
| **kubectl** | >= 1.28 | Kubernetes cluster management | `brew install kubectl` |
| **Docker** | >= 20.x | Build and test images locally | [Docker Desktop](https://docker.com/products/docker-desktop) |
| **jq** | Latest | JSON parsing in scripts | `brew install jq` |

### AWS Account Setup

1. **IAM User with Programmatic Access:**
   ```bash
   # Required IAM permissions (attach these managed policies):
   - AmazonEKSClusterPolicy
   - AmazonEKSWorkerNodePolicy
   - AmazonEC2FullAccess
   - AmazonVPCFullAccess
   - IAMFullAccess (for creating service roles)
   - AmazonEC2ContainerRegistryFullAccess
   ```

2. **Configure AWS Credentials:**
   ```bash
   aws configure
   # Enter:
   # - AWS Access Key ID
   # - AWS Secret Access Key
   # - Default region: eu-central-1
   # - Default output format: json
   ```

3. **Verify Access:**
   ```bash
   aws sts get-caller-identity
   # Should return your account ID and user ARN
   ```

### Cost Awareness

Before proceeding, understand the cost structure:

```
EKS Control Plane:        $0.10/hour  = ~$73/month
3x t3.medium nodes:       $0.125/hour = ~$90/month (3 nodes)
NAT Gateway (2 AZs):      $0.045/hour = ~$65/month
Data Transfer:            ~$5-10/month (testing traffic)
CloudWatch Logs:          ~$5-15/month (depends on verbosity)
ECR Storage:              ~$0.10/GB   = <$1/month (few images)
---------------------------------------------------------
TOTAL:                    ~$240-260/month if running 24/7

CRITICAL: Always run `./scripts/destroy.sh` when not testing!
```

---

## Project Structure

```
veeam/
├── README.md                          # Original project documentation
├── SRE_DEPLOYMENT_GUIDE.md           # This comprehensive guide
│
├── terraform/                         # Infrastructure as Code
│   ├── main.tf                       # Core AWS resources (VPC, EKS, ECR)
│   ├── cloudwatch.tf                 # Logging and monitoring configuration
│   ├── variables.tf                  # Input variables with defaults
│   ├── outputs.tf                    # Output values for scripts
│   ├── terraform.tfvars              # Environment-specific values
│   └── backend.tf                    # (Optional) S3 backend for state
│
├── docker/                            # Container configuration
│   ├── Dockerfile                    # Multi-stage optimized build
│   ├── .dockerignore                 # Exclude unnecessary files
│   └── entrypoint.sh                 # Conditional master/worker startup
│
├── locust/                            # Load test scenarios
│   ├── locustfile.py                 # Main test suite
│   ├── scenarios/
│   │   ├── __init__.py
│   │   ├── jsonplaceholder.py        # JSONPlaceholder API tests
│   │   ├── httpbin.py                # HTTPBin API tests
│   │   └── custom.py                 # Template for custom APIs
│   └── config.py                     # Shared configuration
│
├── kubernetes/                        # K8s manifests
│   ├── namespace.yaml                # Isolated namespace
│   ├── configmap.yaml                # Test configuration
│   ├── master-deployment.yaml        # Locust master (1 replica)
│   ├── master-service.yaml           # LoadBalancer for web UI
│   ├── worker-deployment.yaml        # Locust workers (3-20 replicas)
│   ├── worker-hpa.yaml               # Horizontal Pod Autoscaler
│   └── kustomization.yaml            # (Optional) Kustomize overlay
│
├── scripts/                           # Automation scripts
│   ├── deploy.sh                     # Full deployment orchestration
│   ├── destroy.sh                    # Complete cleanup
│   ├── build-and-push.sh             # Docker build + ECR push
│   ├── update-kubeconfig.sh          # Configure kubectl
│   └── verify-deployment.sh          # Health checks
│
├── pyproject.toml                    # Poetry dependencies
├── poetry.lock                       # Locked dependency versions
└── .gitignore                        # Exclude sensitive files
```

**File Organization Principles:**
- **Separation of Concerns:** Infrastructure (Terraform), application (Docker), orchestration (K8s) are isolated
- **Modularity:** Each Terraform file handles a specific domain (networking, compute, monitoring)
- **Reusability:** Locust scenarios are pluggable modules
- **Automation:** Scripts orchestrate multi-step workflows

---

## Phase 1: Infrastructure Setup with Terraform

### Understanding the Terraform Configuration

#### 1.1 Enhanced main.tf

The Terraform configuration provisions:
- **VPC:** Isolated network with public/private subnets
- **EKS Cluster:** Managed Kubernetes control plane
- **Node Group:** Auto-scaling worker nodes
- **ECR Repository:** Private Docker image registry
- **Security Groups:** Granular network access control

**Key Enhancements to Existing Configuration:**

```hcl
# Add private subnets for worker nodes (security best practice)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name                              = "locust-private-subnet-1"
    "kubernetes.io/role/internal-elb" = "1"  # For internal load balancers
  }
}

# NAT Gateway for private subnet egress (required for external API calls)
resource "aws_eip" "nat_eip_1" {
  domain = "vpc"
  tags = {
    Name = "locust-nat-eip-1"
  }
}

resource "aws_nat_gateway" "nat_gw_1" {
  allocation_id = aws_eip.nat_eip_1.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "locust-nat-gw-1"
  }

  depends_on = [aws_internet_gateway.eks_igw]
}

# Private route table (routes internet traffic through NAT)
resource "aws_route_table" "private_rt_1" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_1.id
  }

  tags = {
    Name = "locust-private-rt-1"
  }
}
```

**Why Private Subnets + NAT Gateway?**
- **Security:** Worker nodes don't have public IPs; can't be directly accessed from internet
- **Egress Control:** All outbound traffic flows through NAT Gateway (allows logging/filtering)
- **EKS Best Practice:** AWS recommends private subnets for production workloads
- **Cost Trade-off:** NAT Gateway adds ~$32/month, but essential for secure production patterns

#### 1.2 CloudWatch Integration (cloudwatch.tf)

```hcl
# CloudWatch Log Group for EKS cluster logs
resource "aws_cloudwatch_log_group" "eks_cluster_logs" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7  # Adjust based on compliance requirements

  tags = {
    Name = "locust-eks-logs"
  }
}

# CloudWatch Log Group for container logs (via FluentBit)
resource "aws_cloudwatch_log_group" "container_logs" {
  name              = "/aws/eks/${var.cluster_name}/containers"
  retention_in_days = 7

  tags = {
    Name = "locust-container-logs"
  }
}

# IAM policy for CloudWatch Logs (attach to node group role)
resource "aws_iam_role_policy" "node_cloudwatch_policy" {
  name = "locust-node-cloudwatch-policy"
  role = aws_iam_role.node_group_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.eks_cluster_logs.arn,
          aws_cloudwatch_log_group.container_logs.arn,
          "${aws_cloudwatch_log_group.eks_cluster_logs.arn}:*",
          "${aws_cloudwatch_log_group.container_logs.arn}:*"
        ]
      }
    ]
  })
}
```

**Why CloudWatch Logging?**
- **Centralized Logs:** All cluster and application logs in one location
- **Debugging:** Trace pod failures, network issues, and performance bottlenecks
- **Compliance:** Many industries require log retention for auditing
- **Cost Control:** 7-day retention balances cost (~$0.50/GB) vs. utility

#### 1.3 Enhanced Security Groups

```hcl
# Security group for worker nodes
resource "aws_security_group" "node_sg" {
  name_prefix = "locust-node-"
  vpc_id      = aws_vpc.eks_vpc.id
  description = "Security group for EKS worker nodes"

  # Allow inbound from cluster control plane (for kubelet)
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_sg.id]
    description     = "Allow control plane to worker node communication"
  }

  # Allow worker-to-worker communication (Locust master-worker)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
    description = "Allow worker nodes to communicate with each other"
  }

  # Allow all outbound traffic (for API calls, image pulls)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "locust-node-sg"
  }
}
```

**Security Hardening Principles:**
- **Least Privilege:** Only allow necessary ports
- **Self-Referencing Rules:** Workers communicate via internal IPs
- **Egress Control:** In production, restrict to specific endpoints

### Deployment Steps

#### Step 1: Initialize Terraform

```bash
cd /home/lostborion/Documents/veeam/terraform

# Download provider plugins (AWS, Kubernetes)
terraform init

# Expected output:
# Initializing provider plugins...
# - hashicorp/aws v5.x.x
# Terraform has been successfully initialized!
```

**What Happens:**
- Downloads AWS provider plugin (~50 MB)
- Creates `.terraform/` directory with provider binaries
- Initializes state backend (local by default)

**Troubleshooting:**
- **Error:** `Provider registry unreachable` → Check internet connection
- **Error:** `Terraform version mismatch` → Upgrade Terraform to >= 1.5

#### Step 2: Validate Configuration

```bash
# Check for syntax errors
terraform validate

# Expected: "Success! The configuration is valid."
```

#### Step 3: Plan Infrastructure Changes

```bash
# Generate execution plan (dry run)
terraform plan -out=tfplan

# Review output carefully:
# - Resources to be created: ~25-30
# - Estimated time: 15-20 minutes
# - No resources should be destroyed (on first run)
```

**Critical Review Items:**
- Verify region is `eu-central-1`
- Check instance types match budget expectations
- Confirm NAT Gateways are in public subnets
- Ensure security groups allow required traffic

#### Step 4: Apply Configuration

```bash
# Provision infrastructure
terraform apply tfplan

# This will:
# 1. Create VPC and subnets (30 seconds)
# 2. Create Internet Gateway and NAT Gateways (1 minute)
# 3. Create security groups and IAM roles (1 minute)
# 4. Provision EKS cluster (10-12 minutes)
# 5. Launch node group (5-7 minutes)
# 6. Create ECR repository (10 seconds)

# Total time: ~18-22 minutes
```

**Progress Monitoring:**
```bash
# In another terminal, watch AWS console or use CLI:
aws eks describe-cluster --name locust-cluster --region eu-central-1 \
  --query 'cluster.status'
# Status progression: CREATING → ACTIVE
```

#### Step 5: Capture Outputs

```bash
# Display all output values
terraform output

# Example output:
# cluster_endpoint = "https://ABC123.gr7.eu-central-1.eks.amazonaws.com"
# cluster_name     = "locust-cluster"
# ecr_repository_url = "123456789.dkr.ecr.eu-central-1.amazonaws.com/locust-load-tests"

# Save to file for scripts
terraform output -json > /tmp/terraform-outputs.json
```

**Why Outputs Matter:**
- **cluster_endpoint:** Used by kubectl to connect
- **ecr_repository_url:** Target for Docker image push
- **cluster_name:** Referenced in update-kubeconfig script

---

## Phase 2: Docker Image Build and Registry

### Enhanced Dockerfile with Multi-Stage Build

**Existing Dockerfile Issues:**
1. Uses `python:3.10-slim` base (~120 MB), acceptable but can optimize further
2. Installs Poetry in runtime image (adds ~30 MB)
3. No health check defined
4. No support for multiple scenarios

**Production-Hardened Dockerfile:**

```dockerfile
# Stage 1: Builder - Install dependencies
FROM python:3.10-slim AS builder

WORKDIR /build

# Install Poetry
RUN pip install --no-cache-dir poetry==1.7.1

# Copy dependency files
COPY pyproject.toml poetry.lock ./

# Export dependencies to requirements.txt (avoid Poetry in runtime)
RUN poetry export -f requirements.txt --output requirements.txt --without-hashes

# Stage 2: Runtime - Minimal image
FROM python:3.10-slim

# Create non-root user (security best practice)
RUN groupadd -r locust && useradd -r -g locust locust

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder /build/requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt && \
    rm requirements.txt

# Copy application code
COPY locust/ ./locust/
COPY docker/entrypoint.sh /entrypoint.sh

# Fix permissions
RUN chown -R locust:locust /app && \
    chmod +x /entrypoint.sh

# Switch to non-root user
USER locust

# Expose Locust ports
EXPOSE 8089 5557

# Health check (pings Locust web interface)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8089').read()" || exit 1

# Use entrypoint script to handle master vs. worker mode
ENTRYPOINT ["/entrypoint.sh"]
```

**Dockerfile Improvements Explained:**

1. **Multi-Stage Build:**
   - **Why:** Separates build tools (Poetry) from runtime, reducing image size by ~40%
   - **Trade-off:** Slightly more complex Dockerfile vs. single-stage simplicity
   - **Result:** Final image ~80 MB vs. ~120 MB

2. **Non-Root User:**
   - **Why:** Security best practice; limits damage if container is compromised
   - **How:** Creates `locust` user with UID 1000 (standard non-root UID)
   - **Impact:** Pod Security Standards (PSS) compliance for restricted workloads

3. **Health Check:**
   - **Why:** Kubernetes uses this to determine if container is healthy
   - **Mechanism:** Pings Locust web UI on port 8089 every 30 seconds
   - **Failure Handling:** After 3 failures, Kubernetes restarts container

4. **Entrypoint Script:**
   - **Why:** Single image supports both master and worker modes
   - **How:** Environment variable `LOCUST_MODE` determines startup command

### Entrypoint Script (docker/entrypoint.sh)

```bash
#!/bin/bash
set -e

# Default values
LOCUST_MODE=${LOCUST_MODE:-master}
TARGET_HOST=${TARGET_HOST:-https://jsonplaceholder.typicode.com}
LOCUST_FILE=${LOCUST_FILE:-locust/locustfile.py}
MASTER_HOST=${MASTER_HOST:-locust-master}

echo "Starting Locust in ${LOCUST_MODE} mode..."
echo "Target host: ${TARGET_HOST}"

if [ "$LOCUST_MODE" = "master" ]; then
    echo "Launching master node..."
    exec locust -f ${LOCUST_FILE} \
        --master \
        --host=${TARGET_HOST} \
        --web-host=0.0.0.0
elif [ "$LOCUST_MODE" = "worker" ]; then
    echo "Launching worker node..."
    echo "Connecting to master at: ${MASTER_HOST}"
    exec locust -f ${LOCUST_FILE} \
        --worker \
        --master-host=${MASTER_HOST}
else
    echo "ERROR: LOCUST_MODE must be 'master' or 'worker'"
    exit 1
fi
```

**Why Entrypoint Script?**
- **Single Image:** Eliminates need for separate master/worker images
- **Configuration via Environment:** Follows 12-factor app principles
- **Fail-Fast:** Exits with error if misconfigured

### Multiple Test Scenarios

**Enhanced Locust Structure:**

```python
# locust/locustfile.py
import os
from locust import HttpUser, task, between

# Determine which scenario to load
SCENARIO = os.getenv("LOCUST_SCENARIO", "jsonplaceholder")

if SCENARIO == "jsonplaceholder":
    from locust.scenarios.jsonplaceholder import JSONPlaceholderUser as TestUser
elif SCENARIO == "httpbin":
    from locust.scenarios.httpbin import HTTPBinUser as TestUser
elif SCENARIO == "custom":
    from locust.scenarios.custom import CustomUser as TestUser
else:
    raise ValueError(f"Unknown scenario: {SCENARIO}")

# Export the selected user class
User = TestUser
```

```python
# locust/scenarios/jsonplaceholder.py
from locust import HttpUser, task, between
import json

class JSONPlaceholderUser(HttpUser):
    """
    Load test scenario for JSONPlaceholder API
    Simulates typical REST API operations: GET, POST, PUT, DELETE
    """
    wait_time = between(1, 3)  # Random wait between requests

    @task(3)  # Weight: 3x more likely than other tasks
    def get_posts(self):
        """Fetch list of posts (most common operation)"""
        with self.client.get("/posts", catch_response=True) as response:
            if response.status_code != 200:
                response.failure(f"Got status {response.status_code}")
            elif len(response.json()) < 100:
                response.failure("Expected at least 100 posts")
            else:
                response.success()

    @task(2)
    def get_single_post(self):
        """Fetch single post details"""
        post_id = self.environment.runner.random.randint(1, 100)
        with self.client.get(f"/posts/{post_id}", catch_response=True) as response:
            if response.status_code != 200:
                response.failure(f"Got status {response.status_code}")
            elif "userId" not in response.text:
                response.failure("Missing userId field")
            else:
                response.success()

    @task(1)
    def create_post(self):
        """Create new post (simulate write operations)"""
        payload = {
            "title": "Load Test Post",
            "body": "This is a test post created by Locust",
            "userId": 1
        }
        with self.client.post("/posts", json=payload, catch_response=True) as response:
            if response.status_code not in [200, 201]:
                response.failure(f"Got status {response.status_code}")
            else:
                response.success()
```

```python
# locust/scenarios/httpbin.py
from locust import HttpUser, task, between

class HTTPBinUser(HttpUser):
    """
    Load test scenario for HTTPBin API
    Tests various HTTP methods and response types
    """
    wait_time = between(0.5, 2)

    @task(4)
    def get_request(self):
        """Test GET with query parameters"""
        self.client.get("/get?param1=value1&param2=value2")

    @task(2)
    def post_json(self):
        """Test POST with JSON payload"""
        self.client.post("/post", json={"key": "value"})

    @task(1)
    def test_delay(self):
        """Test endpoint with artificial delay"""
        self.client.get("/delay/2")

    @task(1)
    def test_status_codes(self):
        """Test various HTTP status codes"""
        self.client.get("/status/200")
        self.client.get("/status/404", name="/status/404 (expected)")
```

**Scenario Selection via ConfigMap:**

```yaml
# kubernetes/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: locust-config
  namespace: locust
data:
  TARGET_HOST: "https://jsonplaceholder.typicode.com"
  LOCUST_SCENARIO: "jsonplaceholder"  # Change to: httpbin, custom
  LOCUST_USERS: "100"
  LOCUST_SPAWN_RATE: "10"
```

### Build and Push Process

**Script: scripts/build-and-push.sh**

```bash
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== Docker Build and ECR Push =====${NC}"

# Get ECR repository URL from Terraform output
ECR_REPO=$(cd terraform && terraform output -raw ecr_repository_url)
AWS_REGION=$(cd terraform && terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")
IMAGE_TAG=${1:-latest}  # Accept tag as argument, default to 'latest'

echo -e "${YELLOW}ECR Repository: ${ECR_REPO}${NC}"
echo -e "${YELLOW}Image Tag: ${IMAGE_TAG}${NC}"

# Authenticate Docker to ECR
echo -e "${GREEN}Step 1: Authenticating to ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REPO}

# Build Docker image
echo -e "${GREEN}Step 2: Building Docker image...${NC}"
docker build \
    --platform linux/amd64 \
    -t locust-load-tests:${IMAGE_TAG} \
    -f docker/Dockerfile \
    .

# Tag for ECR
echo -e "${GREEN}Step 3: Tagging image...${NC}"
docker tag locust-load-tests:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}

# Push to ECR
echo -e "${GREEN}Step 4: Pushing to ECR...${NC}"
docker push ${ECR_REPO}:${IMAGE_TAG}

echo -e "${GREEN}✓ Image successfully pushed to ${ECR_REPO}:${IMAGE_TAG}${NC}"

# Update Kubernetes deployments to use new tag
if [ "$IMAGE_TAG" != "latest" ]; then
    echo -e "${YELLOW}To deploy this version, update kubernetes manifests with image tag: ${IMAGE_TAG}${NC}"
fi
```

**Usage:**

```bash
# Build and push with 'latest' tag
./scripts/build-and-push.sh

# Build and push with version tag
./scripts/build-and-push.sh v1.2.0

# Build and push with git commit SHA (recommended for production)
./scripts/build-and-push.sh $(git rev-parse --short HEAD)
```

**Why Version Tagging Matters:**
- **latest:** Convenient for development, but risky (can't rollback)
- **Semantic Versions:** Explicit versioning enables controlled rollouts
- **Git SHA:** Ensures exact code-to-image traceability

---

## Phase 3: Kubernetes Deployment

### Namespace Isolation

```yaml
# kubernetes/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: locust
  labels:
    name: locust
    environment: load-testing
```

**Why Separate Namespace?**
- **Resource Isolation:** Quotas and limits don't affect other applications
- **RBAC Scoping:** Permissions apply only to this namespace
- **Cleanup:** `kubectl delete namespace locust` removes everything

### ConfigMap for Test Configuration

```yaml
# kubernetes/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: locust-config
  namespace: locust
data:
  # Target API to test
  TARGET_HOST: "https://jsonplaceholder.typicode.com"

  # Which test scenario to run (jsonplaceholder, httpbin, custom)
  LOCUST_SCENARIO: "jsonplaceholder"

  # Test parameters (can be overridden in Locust web UI)
  LOCUST_USERS: "100"
  LOCUST_SPAWN_RATE: "10"

  # Logging level
  LOG_LEVEL: "INFO"
```

### Master Deployment

```yaml
# kubernetes/master-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: locust-master
  namespace: locust
  labels:
    app: locust
    component: master
spec:
  replicas: 1  # Always 1 master
  selector:
    matchLabels:
      app: locust
      component: master
  template:
    metadata:
      labels:
        app: locust
        component: master
    spec:
      containers:
      - name: locust
        image: <ECR_REPO_URL>:latest  # Replace with actual URL
        imagePullPolicy: Always
        env:
        - name: LOCUST_MODE
          value: "master"
        - name: TARGET_HOST
          valueFrom:
            configMapKeyRef:
              name: locust-config
              key: TARGET_HOST
        - name: LOCUST_SCENARIO
          valueFrom:
            configMapKeyRef:
              name: locust-config
              key: LOCUST_SCENARIO
        ports:
        - containerPort: 8089  # Web UI
          name: web
          protocol: TCP
        - containerPort: 5557  # Master communication
          name: master
          protocol: TCP
        resources:
          requests:
            cpu: 500m      # 0.5 CPU cores
            memory: 512Mi  # 512 MB
          limits:
            cpu: 1000m     # 1 CPU core
            memory: 1Gi    # 1 GB
        livenessProbe:
          httpGet:
            path: /
            port: 8089
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 8089
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
```

**Master Resource Allocation Rationale:**

| Resource | Request | Limit | Rationale |
|----------|---------|-------|-----------|
| CPU | 500m | 1000m | Master doesn't generate load; primarily aggregates metrics and serves UI |
| Memory | 512Mi | 1Gi | Stores aggregated stats from all workers; 1GB handles 20 workers easily |

**Probes Configuration:**
- **Liveness:** Restarts container if web UI stops responding (assumes master is crashed)
- **Readiness:** Removes pod from service if not ready (prevents routing to uninitialized master)
- **Timing:** 30s initial delay accounts for Python startup time

### Master Service (LoadBalancer)

```yaml
# kubernetes/master-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: locust-master
  namespace: locust
  labels:
    app: locust
    component: master
spec:
  type: LoadBalancer  # Exposes web UI externally
  selector:
    app: locust
    component: master
  ports:
  - port: 8089
    targetPort: 8089
    protocol: TCP
    name: web
  - port: 5557
    targetPort: 5557
    protocol: TCP
    name: master-communication
```

**LoadBalancer vs. NodePort vs. ClusterIP:**

| Type | Use Case | External Access | Cost |
|------|----------|-----------------|------|
| **LoadBalancer** | Production (chosen here) | Yes, via AWS ELB | ~$18/month |
| **NodePort** | Development | Yes, via node IP:port | Free |
| **ClusterIP** | Internal only | No | Free |

**Why LoadBalancer?**
- **Production Pattern:** Managed AWS Network Load Balancer (NLB) provides stable endpoint
- **Security:** Can attach WAF, SSL/TLS termination
- **HA:** ELB automatically routes to healthy pods
- **Trade-off:** Costs ~$18/month; for temporary testing, use NodePort instead

**Alternative (NodePort):**

```yaml
spec:
  type: NodePort
  ports:
  - port: 8089
    targetPort: 8089
    nodePort: 30089  # Access via <any-node-ip>:30089
```

### Worker Deployment

```yaml
# kubernetes/worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: locust-worker
  namespace: locust
  labels:
    app: locust
    component: worker
spec:
  replicas: 3  # Initial count; HPA will adjust
  selector:
    matchLabels:
      app: locust
      component: worker
  template:
    metadata:
      labels:
        app: locust
        component: worker
    spec:
      containers:
      - name: locust
        image: <ECR_REPO_URL>:latest  # Replace with actual URL
        imagePullPolicy: Always
        env:
        - name: LOCUST_MODE
          value: "worker"
        - name: MASTER_HOST
          value: "locust-master"  # DNS name of master service
        - name: TARGET_HOST
          valueFrom:
            configMapKeyRef:
              name: locust-config
              key: TARGET_HOST
        - name: LOCUST_SCENARIO
          valueFrom:
            configMapKeyRef:
              name: locust-config
              key: LOCUST_SCENARIO
        resources:
          requests:
            cpu: 1000m     # 1 CPU core
            memory: 512Mi  # 512 MB
          limits:
            cpu: 2000m     # 2 CPU cores
            memory: 1Gi    # 1 GB
        livenessProbe:
          exec:
            command:
            - sh
            - -c
            - "pgrep -f 'locust.*worker' || exit 1"
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
```

**Worker Resource Allocation:**

| Resource | Request | Limit | Rationale |
|----------|---------|-------|-----------|
| CPU | 1000m | 2000m | Workers generate HTTP requests; CPU-intensive during high RPS |
| Memory | 512Mi | 1Gi | Stores response data; 1GB handles 1000+ RPS comfortably |

**Why Higher CPU for Workers?**
- **Load Generation:** Each worker executes HTTP requests, processes responses
- **Concurrency:** Locust uses gevent for async I/O; CPU scales with virtual users
- **Realistic Sizing:** 1 CPU core ~ 500-1000 RPS for typical REST APIs

### Horizontal Pod Autoscaler (HPA)

```yaml
# kubernetes/worker-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: locust-worker-hpa
  namespace: locust
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: locust-worker
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Scale when avg CPU > 70%
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Scale when avg memory > 80%
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60  # Wait 60s before scaling up again
      policies:
      - type: Percent
        value: 50      # Scale up by 50% of current replicas
        periodSeconds: 60
      - type: Pods
        value: 2       # Or add 2 pods, whichever is greater
        periodSeconds: 60
      selectPolicy: Max  # Use the policy that scales faster
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 minutes before scaling down
      policies:
      - type: Percent
        value: 10      # Scale down by 10% of current replicas
        periodSeconds: 60
```

**HPA Configuration Deep Dive:**

**Scaling Triggers:**
1. **CPU > 70%:** Triggers scale-up (e.g., when RPS increases)
2. **Memory > 80%:** Triggers scale-up (e.g., when responses are large)
3. **Both metrics:** HPA uses the metric that requires more pods

**Scaling Behavior:**
- **Scale-Up:**
  - **Fast Response:** Adds 50% more pods OR 2 pods (whichever is larger)
  - **Example:** 4 workers at 80% CPU → scales to 6 workers (50% increase)
  - **Stabilization:** Waits 60s to avoid thrashing

- **Scale-Down:**
  - **Conservative:** Removes only 10% of pods every 60 seconds
  - **Example:** 20 workers at 40% CPU → scales down to 18 workers
  - **Stabilization:** Waits 5 minutes to avoid premature scale-down

**Why These Numbers?**
- **70% CPU Threshold:** Provides 30% headroom for request spikes
- **80% Memory Threshold:** Prevents OOM kills (which are disruptive)
- **Asymmetric Scaling:** Fast scale-up (respond to load), slow scale-down (avoid oscillation)
- **Min 3 / Max 20:** Baseline capacity + cost cap

**Cost Example:**
```
Scenario: Load test ramps to 10,000 RPS
- Initial: 3 workers at 30% CPU
- Ramp-up: HPA scales to 12 workers (70% CPU average)
- Peak: 12 workers * $0.0416/hr (t3.medium) = $0.50/hour
- Test duration: 2 hours = $1.00 total cost
```

### Deployment Script

**Script: scripts/update-kubeconfig.sh**

```bash
#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Updating kubeconfig for EKS cluster...${NC}"

CLUSTER_NAME=$(cd terraform && terraform output -raw cluster_name)
AWS_REGION=$(cd terraform && terraform output -raw aws_region 2>/dev/null || echo "eu-central-1")

aws eks update-kubeconfig \
    --region ${AWS_REGION} \
    --name ${CLUSTER_NAME}

echo -e "${GREEN}✓ Kubeconfig updated. Testing connection...${NC}"
kubectl cluster-info
kubectl get nodes
```

**Script: scripts/deploy-k8s.sh**

```bash
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}===== Deploying to Kubernetes =====${NC}"

# Update kubeconfig
./scripts/update-kubeconfig.sh

# Get ECR repository URL
ECR_REPO=$(cd terraform && terraform output -raw ecr_repository_url)

# Update image references in manifests
echo -e "${YELLOW}Updating image references to ${ECR_REPO}:latest${NC}"
sed -i.bak "s|<ECR_REPO_URL>|${ECR_REPO}|g" kubernetes/*.yaml

# Deploy in order
echo -e "${GREEN}Creating namespace...${NC}"
kubectl apply -f kubernetes/namespace.yaml

echo -e "${GREEN}Creating ConfigMap...${NC}"
kubectl apply -f kubernetes/configmap.yaml

echo -e "${GREEN}Deploying Locust master...${NC}"
kubectl apply -f kubernetes/master-deployment.yaml
kubectl apply -f kubernetes/master-service.yaml

echo -e "${GREEN}Deploying Locust workers...${NC}"
kubectl apply -f kubernetes/worker-deployment.yaml
kubectl apply -f kubernetes/worker-hpa.yaml

# Wait for deployments
echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s \
    deployment/locust-master -n locust
kubectl wait --for=condition=available --timeout=300s \
    deployment/locust-worker -n locust

echo -e "${GREEN}✓ Deployment complete!${NC}"

# Get LoadBalancer URL
echo -e "${YELLOW}Fetching Locust web UI URL...${NC}"
kubectl get svc locust-master -n locust
echo -e "${GREEN}Access the UI at: http://<EXTERNAL-IP>:8089${NC}"
```

---

## Phase 4: Deployment Execution

### Master Deployment Script

**Script: scripts/deploy.sh (Full Orchestration)**

```bash
#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "=============================================="
echo "  Locust on AWS EKS - Full Deployment"
echo "=============================================="
echo -e "${NC}"

# Check prerequisites
echo -e "${GREEN}Step 1: Checking prerequisites...${NC}"
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}ERROR: terraform not found${NC}"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}ERROR: aws CLI not found${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}ERROR: kubectl not found${NC}"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo -e "${RED}ERROR: docker not found${NC}"; exit 1; }

aws sts get-caller-identity >/dev/null 2>&1 || { echo -e "${RED}ERROR: AWS credentials not configured${NC}"; exit 1; }
echo -e "${GREEN}✓ All prerequisites met${NC}"

# Deploy infrastructure
echo -e "\n${GREEN}Step 2: Deploying AWS infrastructure...${NC}"
cd terraform
terraform init -upgrade
terraform apply -auto-approve
cd ..
echo -e "${GREEN}✓ Infrastructure deployed${NC}"

# Build and push Docker image
echo -e "\n${GREEN}Step 3: Building and pushing Docker image...${NC}"
./scripts/build-and-push.sh
echo -e "${GREEN}✓ Docker image published${NC}"

# Deploy to Kubernetes
echo -e "\n${GREEN}Step 4: Deploying to Kubernetes...${NC}"
./scripts/deploy-k8s.sh
echo -e "${GREEN}✓ Kubernetes deployment complete${NC}"

# Display access information
echo -e "\n${BLUE}=============================================="
echo "  Deployment Summary"
echo "=============================================="
echo -e "${NC}"

CLUSTER_NAME=$(cd terraform && terraform output -raw cluster_name)
CLUSTER_ENDPOINT=$(cd terraform && terraform output -raw cluster_endpoint)
ECR_REPO=$(cd terraform && terraform output -raw ecr_repository_url)

echo -e "${YELLOW}EKS Cluster:${NC} ${CLUSTER_NAME}"
echo -e "${YELLOW}Cluster Endpoint:${NC} ${CLUSTER_ENDPOINT}"
echo -e "${YELLOW}ECR Repository:${NC} ${ECR_REPO}"

echo -e "\n${YELLOW}Waiting for LoadBalancer to assign external IP...${NC}"
for i in {1..60}; do
    LB_IP=$(kubectl get svc locust-master -n locust -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$LB_IP" ]; then
        echo -e "\n${GREEN}✓ Locust Web UI: http://${LB_IP}:8089${NC}"
        break
    fi
    echo -n "."
    sleep 5
done

echo -e "\n${BLUE}=============================================="
echo "  Next Steps"
echo "=============================================="
echo -e "${NC}"
echo "1. Access Locust UI at the URL above"
echo "2. Monitor pods: kubectl get pods -n locust -w"
echo "3. View logs: kubectl logs -f deployment/locust-master -n locust"
echo "4. Check HPA: kubectl get hpa -n locust"
echo ""
echo -e "${RED}IMPORTANT: When finished, run ./scripts/destroy.sh to avoid charges${NC}"
```

**Usage:**

```bash
# Make script executable
chmod +x scripts/deploy.sh

# Run full deployment
./scripts/deploy.sh

# Expected duration:
# - Infrastructure: 18-22 minutes
# - Docker build/push: 3-5 minutes
# - K8s deployment: 2-3 minutes
# - Total: ~25-30 minutes
```

---

## Monitoring and Verification

### Verification Checklist

**Script: scripts/verify-deployment.sh**

```bash
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}===== Deployment Verification =====${NC}\n"

# Check Terraform state
echo -e "${YELLOW}1. Terraform Resources${NC}"
cd terraform
terraform state list | grep -E "aws_eks_cluster|aws_eks_node_group|aws_ecr_repository" && \
    echo -e "${GREEN}✓ Core infrastructure exists${NC}" || \
    echo -e "${RED}✗ Infrastructure missing${NC}"
cd ..

# Check EKS cluster
echo -e "\n${YELLOW}2. EKS Cluster Status${NC}"
CLUSTER_STATUS=$(aws eks describe-cluster --name locust-cluster --region eu-central-1 --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}✓ Cluster is ACTIVE${NC}"
else
    echo -e "${RED}✗ Cluster status: ${CLUSTER_STATUS}${NC}"
fi

# Check node group
echo -e "\n${YELLOW}3. EKS Node Group${NC}"
kubectl get nodes -o wide
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -ge 3 ]; then
    echo -e "${GREEN}✓ ${NODE_COUNT} nodes running${NC}"
else
    echo -e "${RED}✗ Only ${NODE_COUNT} nodes (expected 3+)${NC}"
fi

# Check namespace
echo -e "\n${YELLOW}4. Locust Namespace${NC}"
kubectl get namespace locust >/dev/null 2>&1 && \
    echo -e "${GREEN}✓ Namespace exists${NC}" || \
    echo -e "${RED}✗ Namespace not found${NC}"

# Check deployments
echo -e "\n${YELLOW}5. Deployments${NC}"
kubectl get deployments -n locust
MASTER_READY=$(kubectl get deployment locust-master -n locust -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WORKER_READY=$(kubectl get deployment locust-worker -n locust -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

[ "$MASTER_READY" = "1" ] && echo -e "${GREEN}✓ Master ready${NC}" || echo -e "${RED}✗ Master not ready${NC}"
[ "$WORKER_READY" -ge "3" ] && echo -e "${GREEN}✓ ${WORKER_READY} workers ready${NC}" || echo -e "${RED}✗ Only ${WORKER_READY} workers${NC}"

# Check services
echo -e "\n${YELLOW}6. Services${NC}"
kubectl get svc -n locust
LB_IP=$(kubectl get svc locust-master -n locust -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$LB_IP" ]; then
    echo -e "${GREEN}✓ LoadBalancer: http://${LB_IP}:8089${NC}"
else
    echo -e "${RED}✗ LoadBalancer not ready (may take 2-3 minutes)${NC}"
fi

# Check HPA
echo -e "\n${YELLOW}7. Horizontal Pod Autoscaler${NC}"
kubectl get hpa -n locust
HPA_EXISTS=$(kubectl get hpa locust-worker-hpa -n locust >/dev/null 2>&1 && echo "yes" || echo "no")
[ "$HPA_EXISTS" = "yes" ] && echo -e "${GREEN}✓ HPA configured${NC}" || echo -e "${RED}✗ HPA missing${NC}"

# Check CloudWatch logs
echo -e "\n${YELLOW}8. CloudWatch Logs${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/locust-cluster" --region eu-central-1 --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
if [ -n "$LOG_GROUPS" ]; then
    echo -e "${GREEN}✓ Log groups: ${LOG_GROUPS}${NC}"
else
    echo -e "${RED}✗ No log groups found${NC}"
fi

# Summary
echo -e "\n${YELLOW}===== Summary =====${NC}"
echo "Run the following commands for detailed inspection:"
echo "  kubectl logs -f deployment/locust-master -n locust"
echo "  kubectl logs -f deployment/locust-worker -n locust"
echo "  kubectl top pods -n locust"
echo "  kubectl describe hpa locust-worker-hpa -n locust"
```

### Monitoring Commands

```bash
# Real-time pod status
kubectl get pods -n locust -w

# View master logs
kubectl logs -f deployment/locust-master -n locust

# View worker logs (all pods)
kubectl logs -f deployment/locust-worker -n locust --all-containers=true

# Check resource usage
kubectl top pods -n locust
kubectl top nodes

# Inspect HPA status
kubectl get hpa -n locust
kubectl describe hpa locust-worker-hpa -n locust

# View events (useful for troubleshooting)
kubectl get events -n locust --sort-by='.lastTimestamp'
```

### CloudWatch Logs Access

```bash
# List log streams
aws logs describe-log-streams \
    --log-group-name /aws/eks/locust-cluster/cluster \
    --region eu-central-1 \
    --max-items 10

# Tail cluster logs
aws logs tail /aws/eks/locust-cluster/cluster \
    --follow \
    --region eu-central-1

# Filter for errors
aws logs filter-log-events \
    --log-group-name /aws/eks/locust-cluster/cluster \
    --filter-pattern "ERROR" \
    --region eu-central-1
```

### Grafana Dashboard (Optional)

For production monitoring, deploy Prometheus + Grafana:

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus + Grafana stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace

# Access Grafana (default: admin/prom-operator)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Import Kubernetes dashboards:
# - Dashboard ID 6417 (Kubernetes Cluster Monitoring)
# - Dashboard ID 12120 (Kubernetes Node Exporter)
```

---

## Cost Management and Cleanup

### Understanding Costs

**Hourly Breakdown:**

| Component | Hourly Cost | Monthly (24/7) | Notes |
|-----------|-------------|----------------|-------|
| EKS Control Plane | $0.10 | $73 | Fixed cost |
| 3x t3.medium nodes | $0.125 | $90 | Baseline nodes |
| NAT Gateway (2 AZs) | $0.09 | $65 | Network egress |
| LoadBalancer (NLB) | $0.0225 | $16 | Locust UI access |
| CloudWatch Logs | ~$0.007 | ~$5 | Variable based on logs |
| ECR Storage | - | <$1 | $0.10/GB, few images |
| **TOTAL** | **~$0.34/hr** | **~$250/month** | If running 24/7 |

**Cost Optimization Strategies:**

1. **Destroy When Idle (Recommended):**
   ```bash
   # Costs only during testing
   ./scripts/deploy.sh    # Start test: ~$0.34/hour
   # Run load test (e.g., 2 hours)
   ./scripts/destroy.sh   # Total cost: ~$0.68
   ```

2. **Scale Down Node Group:**
   ```bash
   # Reduce to 1 node during idle periods
   aws eks update-nodegroup-config \
       --cluster-name locust-cluster \
       --nodegroup-name locust-nodes \
       --scaling-config minSize=1,maxSize=1,desiredSize=1 \
       --region eu-central-1

   # Saves: ~$60/month
   ```

3. **Use Spot Instances (Advanced):**
   ```hcl
   # In terraform/main.tf, add to node group:
   capacity_type = "SPOT"

   # Savings: ~60-70% discount on node costs
   # Risk: Nodes can be reclaimed with 2-minute notice
   ```

4. **Switch to NodePort (No LoadBalancer):**
   ```yaml
   # kubernetes/master-service.yaml
   spec:
     type: NodePort  # Instead of LoadBalancer

   # Access via: http://<node-public-ip>:30089
   # Savings: $16/month
   ```

### Destruction Script

**Script: scripts/destroy.sh**

```bash
#!/bin/bash
set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}"
echo "=============================================="
echo "  WARNING: DESTRUCTIVE OPERATION"
echo "=============================================="
echo -e "${NC}"
echo "This will destroy ALL resources:"
echo "  - EKS cluster and node group"
echo "  - VPC, subnets, NAT gateways"
echo "  - ECR repository and Docker images"
echo "  - CloudWatch log groups"
echo ""
read -p "Type 'destroy' to confirm: " CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# Delete Kubernetes resources first (faster than waiting for Terraform)
echo -e "\n${YELLOW}Step 1: Deleting Kubernetes resources...${NC}"
kubectl delete namespace locust --ignore-not-found=true
echo -e "${GREEN}✓ Kubernetes resources deleted${NC}"

# Delete ECR images (Terraform can't delete non-empty repositories)
echo -e "\n${YELLOW}Step 2: Deleting ECR images...${NC}"
ECR_REPO=$(cd terraform && terraform output -raw ecr_repository_url 2>/dev/null | cut -d'/' -f2 || echo "")
if [ -n "$ECR_REPO" ]; then
    aws ecr batch-delete-image \
        --repository-name ${ECR_REPO} \
        --image-ids "$(aws ecr list-images --repository-name ${ECR_REPO} --region eu-central-1 --query 'imageIds[*]' --output json)" \
        --region eu-central-1 2>/dev/null || echo "No images to delete"
    echo -e "${GREEN}✓ ECR images deleted${NC}"
fi

# Destroy Terraform infrastructure
echo -e "\n${YELLOW}Step 3: Destroying Terraform infrastructure...${NC}"
cd terraform
terraform destroy -auto-approve
cd ..
echo -e "${GREEN}✓ Infrastructure destroyed${NC}"

# Optional: Delete CloudWatch log groups (not managed by Terraform)
echo -e "\n${YELLOW}Step 4: Deleting CloudWatch log groups...${NC}"
aws logs delete-log-group --log-group-name /aws/eks/locust-cluster/cluster --region eu-central-1 2>/dev/null || echo "Log group already deleted"
aws logs delete-log-group --log-group-name /aws/eks/locust-cluster/containers --region eu-central-1 2>/dev/null || echo "Log group already deleted"
echo -e "${GREEN}✓ Log groups deleted${NC}"

echo -e "\n${GREEN}=============================================="
echo "  Cleanup Complete"
echo "=============================================="
echo -e "${NC}"
echo "All resources have been destroyed."
echo "Verify in AWS Console: VPC, EKS, ECR sections should be empty."
```

**Usage:**

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Duration: 8-12 minutes
# - K8s namespace deletion: 1-2 minutes
# - EKS cluster deletion: 5-8 minutes
# - VPC cleanup: 2-3 minutes
```

**Post-Destruction Verification:**

```bash
# Check no EKS clusters
aws eks list-clusters --region eu-central-1
# Output: {"clusters": []}

# Check no Terraform resources
cd terraform && terraform state list
# Output: (empty)

# Check AWS Console:
# - EC2 → VPCs: Should show only default VPC
# - EKS → Clusters: Should be empty
# - ECR → Repositories: Should be empty
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Terraform Apply Fails with "Subnet Not Found"

**Symptom:**
```
Error: creating EKS Node Group: InvalidParameterException:
Subnets [subnet-xxx] are not found
```

**Cause:** Subnets were not created in the correct availability zones.

**Solution:**
```bash
# Check available AZs in eu-central-1
aws ec2 describe-availability-zones --region eu-central-1 --query 'AvailabilityZones[*].ZoneName'

# Ensure at least 2 AZs are available
# If only 1 AZ, modify terraform/main.tf to use single AZ:
# - Remove public_subnet_2 and private_subnet_2
# - Update node group to use only subnet_1
```

#### 2. Docker Build Fails on M1/M2 Mac

**Symptom:**
```
exec /usr/local/bin/python: exec format error
```

**Cause:** M1/M2 Macs use ARM64 architecture; EKS nodes use AMD64.

**Solution:**
```bash
# Build for AMD64 explicitly
docker build --platform linux/amd64 -t locust-load-tests:latest .

# Or use buildx for multi-platform builds
docker buildx create --use
docker buildx build --platform linux/amd64 -t locust-load-tests:latest --load .
```

#### 3. EKS Nodes Stuck in "NotReady" State

**Symptom:**
```bash
kubectl get nodes
# Output: locust-node-xxx   NotReady   <none>   5m
```

**Cause:** CNI plugin not initialized or IAM permissions missing.

**Solution:**
```bash
# Check kubelet logs on node
kubectl describe node <node-name>

# Common fixes:
# 1. Verify IAM role has AmazonEKS_CNI_Policy
aws iam list-attached-role-policies --role-name <node-role-name>

# 2. Check VPC CNI pods
kubectl get pods -n kube-system | grep aws-node

# 3. Restart VPC CNI daemonset
kubectl rollout restart daemonset aws-node -n kube-system
```

#### 4. LoadBalancer Service Stuck in "Pending"

**Symptom:**
```bash
kubectl get svc locust-master -n locust
# EXTERNAL-IP shows <pending> for >5 minutes
```

**Cause:** AWS Load Balancer Controller not installed or IAM permissions missing.

**Solution:**
```bash
# Check service events
kubectl describe svc locust-master -n locust

# Install AWS Load Balancer Controller (if not present)
eksctl utils associate-iam-oidc-provider \
    --region eu-central-1 \
    --cluster locust-cluster \
    --approve

# Create IAM policy and service account (detailed instructions in AWS docs)
# Shortcut: Use NodePort instead of LoadBalancer for testing
```

#### 5. HPA Not Scaling Workers

**Symptom:**
```bash
kubectl get hpa -n locust
# TARGETS shows <unknown>/70%
```

**Cause:** Metrics Server not installed in cluster.

**Solution:**
```bash
# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify installation
kubectl get deployment metrics-server -n kube-system

# Test metrics collection
kubectl top pods -n locust
```

#### 6. Workers Can't Connect to Master

**Symptom:**
```bash
kubectl logs -f deployment/locust-worker -n locust
# Output: "Failed to connect to master at locust-master:5557"
```

**Cause:** DNS resolution issue or service not created.

**Solution:**
```bash
# Check if master service exists
kubectl get svc locust-master -n locust

# Test DNS resolution from worker pod
kubectl exec -it deployment/locust-worker -n locust -- nslookup locust-master

# Check if master is listening on port 5557
kubectl exec -it deployment/locust-master -n locust -- netstat -tlnp | grep 5557

# Verify master logs show "Starting master node"
kubectl logs deployment/locust-master -n locust
```

#### 7. ECR Authentication Fails

**Symptom:**
```
Error response from daemon: Get https://123456789.dkr.ecr.eu-central-1.amazonaws.com/v2/:
no basic auth credentials
```

**Cause:** Docker not authenticated to ECR.

**Solution:**
```bash
# Re-authenticate to ECR
AWS_REGION=eu-central-1
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin \
    $(aws ecr describe-repositories --repository-names locust-load-tests --region ${AWS_REGION} --query 'repositories[0].repositoryUri' --output text | cut -d'/' -f1)

# Verify authentication
docker pull <ECR_REPO_URL>:latest
```

#### 8. High AWS Costs

**Symptom:** AWS bill higher than expected.

**Cause:** Resources left running after testing.

**Solution:**
```bash
# Audit running resources
aws ec2 describe-instances --region eu-central-1 --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]' --output table
aws eks list-clusters --region eu-central-1
aws ec2 describe-nat-gateways --region eu-central-1 --filter "Name=state,Values=available"

# Destroy immediately if not needed
./scripts/destroy.sh

# Set up billing alerts in AWS Console:
# Billing → Billing Preferences → Receive Billing Alerts
# CloudWatch → Alarms → Create Alarm → Billing → EstimatedCharges
```

---

## Production Considerations

### Security Hardening

For production deployments, implement these additional security measures:

#### 1. Private EKS API Endpoint

```hcl
# terraform/main.tf
resource "aws_eks_cluster" "locust_cluster" {
  # ...
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false  # Disable public access
    # Access only via VPN/bastion
  }
}
```

#### 2. Secrets Management

```bash
# Use AWS Secrets Manager for sensitive data
aws secretsmanager create-secret \
    --name locust/api-credentials \
    --secret-string '{"api_key":"xxx","api_secret":"yyy"}' \
    --region eu-central-1

# Reference in Kubernetes via External Secrets Operator
# https://external-secrets.io/
```

#### 3. Network Policies

```yaml
# kubernetes/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: locust-worker-policy
  namespace: locust
spec:
  podSelector:
    matchLabels:
      component: worker
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          component: master
  egress:
  - to:
    - podSelector:
        matchLabels:
          component: master
  - to:  # Allow external API calls
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
```

#### 4. Pod Security Standards

```yaml
# kubernetes/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: locust
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### High Availability

#### 1. Multi-Region Deployment

For global load testing, deploy clusters in multiple regions:

```bash
# Deploy to eu-central-1 (Frankfurt)
terraform workspace new eu-central-1
terraform apply -var="aws_region=eu-central-1"

# Deploy to us-east-1 (Virginia)
terraform workspace new us-east-1
terraform apply -var="aws_region=us-east-1"

# Aggregate results using Locust distributed mode across regions
```

#### 2. Cluster Autoscaler

```bash
# Install Cluster Autoscaler for automatic node scaling
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
    --set autoDiscovery.clusterName=locust-cluster \
    --set awsRegion=eu-central-1 \
    --namespace kube-system
```

### CI/CD Integration

#### GitHub Actions Example

```yaml
# .github/workflows/deploy-locust.yml
name: Deploy Locust to EKS

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: eu-central-1

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2

    - name: Terraform Apply
      run: |
        cd terraform
        terraform init
        terraform apply -auto-approve

    - name: Build and Push Docker Image
      run: |
        export IMAGE_TAG=${GITHUB_SHA::7}
        ./scripts/build-and-push.sh $IMAGE_TAG

    - name: Deploy to Kubernetes
      run: |
        aws eks update-kubeconfig --name locust-cluster --region eu-central-1
        kubectl set image deployment/locust-master locust=<ECR_REPO>:${GITHUB_SHA::7} -n locust
        kubectl set image deployment/locust-worker locust=<ECR_REPO>:${GITHUB_SHA::7} -n locust
```

---

## Alternative Test APIs

While this guide uses JSONPlaceholder, here are other public APIs suitable for load testing:

| API | URL | Features | Rate Limits |
|-----|-----|----------|-------------|
| **JSONPlaceholder** | https://jsonplaceholder.typicode.com | REST, CRUD operations | None (be respectful) |
| **HTTPBin** | https://httpbin.org | HTTP methods, status codes, auth | None |
| **ReqRes** | https://reqres.in | User data, pagination | None |
| **Faker API** | https://fakerapi.it/api/v1 | Random data generation | 1000 req/day |
| **OpenWeather** | https://openweathermap.org/api | Weather data | 60 req/min (free tier) |

**Switching Test Target:**

```bash
# Update ConfigMap
kubectl edit configmap locust-config -n locust

# Change TARGET_HOST to desired API
data:
  TARGET_HOST: "https://httpbin.org"
  LOCUST_SCENARIO: "httpbin"

# Restart deployments to pick up new config
kubectl rollout restart deployment/locust-master -n locust
kubectl rollout restart deployment/locust-worker -n locust
```

---

## Summary Checklist

### Pre-Deployment
- [ ] AWS CLI configured with valid credentials
- [ ] Terraform >= 1.5 installed
- [ ] kubectl >= 1.28 installed
- [ ] Docker installed and running
- [ ] Cost awareness: Understand ~$0.34/hour runtime cost

### Deployment
- [ ] Run `./scripts/deploy.sh` (takes ~25 minutes)
- [ ] Verify infrastructure with `./scripts/verify-deployment.sh`
- [ ] Access Locust UI at LoadBalancer URL
- [ ] Monitor pod status: `kubectl get pods -n locust -w`

### Testing
- [ ] Configure test in Locust UI (users, spawn rate, duration)
- [ ] Monitor HPA scaling: `kubectl get hpa -n locust -w`
- [ ] Check CloudWatch logs for errors
- [ ] Export results from Locust UI (CSV, HTML reports)

### Post-Testing
- [ ] Run `./scripts/destroy.sh` to delete all resources
- [ ] Verify AWS Console shows no remaining resources
- [ ] Review AWS bill to confirm resource deletion

---

## Conclusion

This guide provides a production-ready, enterprise-grade infrastructure for distributed load testing using Locust on AWS EKS. Key takeaways:

**Design Principles:**
- **Infrastructure as Code:** Everything is versioned, repeatable, and auditable
- **Security by Default:** Private subnets, IAM roles, non-root containers
- **Auto-Scaling:** HPA adjusts worker count based on load
- **Observability:** CloudWatch logs and metrics for debugging
- **Cost Conscious:** Single-command destruction prevents surprise bills

**Operational Best Practices:**
- Always destroy resources when not in use (`./scripts/destroy.sh`)
- Tag resources with owner/project for cost allocation
- Use git tags for Docker images to enable rollback
- Monitor AWS billing daily during initial deployment
- Document any customizations in this guide

**Next Steps:**
- Customize Locust scenarios for your specific APIs
- Integrate with CI/CD pipeline for automated testing
- Add Prometheus/Grafana for advanced metrics
- Implement blue-green deployments for zero-downtime updates
- Scale to multi-region for global load distribution

For questions or issues, refer to:
- AWS EKS Documentation: https://docs.aws.amazon.com/eks/
- Locust Documentation: https://docs.locust.io/
- Kubernetes Documentation: https://kubernetes.io/docs/

**Estimated Reading Time:** 45-60 minutes
**Estimated Deployment Time:** 25-30 minutes
**Skill Level:** Intermediate SRE/DevOps Engineer
