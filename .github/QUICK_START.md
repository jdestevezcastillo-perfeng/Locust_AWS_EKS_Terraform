# Quick Start Guide - GitHub Actions Deployment

Get your Locust infrastructure deployed in 5 steps!

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] AWS account with admin access
- [ ] GitHub repository access with admin permissions
- [ ] AWS CLI installed locally (for setup)

## Step 1: Create AWS Backend Resources (5 minutes)

Run this script locally to create the Terraform state backend:

```bash
#!/bin/bash
# File: setup-backend.sh

REGION="eu-central-1"
STATE_BUCKET="my-company-terraform-state"  # Change this to your unique bucket name
LOCK_TABLE="terraform-state-lock"

# Create S3 bucket
aws s3 mb "s3://${STATE_BUCKET}" --region "${REGION}"

# Configure bucket
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table
aws dynamodb create-table \
  --table-name "${LOCK_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}"

echo "Setup complete!"
echo "Bucket: ${STATE_BUCKET}"
echo "Table: ${LOCK_TABLE}"
```

## Step 2: Configure GitHub Secrets (3 minutes)

Go to your GitHub repository:

**Settings > Secrets and variables > Actions > New repository secret**

Add these 5 secrets:

| Secret Name | Value | Where to find |
|-------------|-------|---------------|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | AWS Console > IAM > Security credentials |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG...` | Same as above |
| `AWS_REGION` | `eu-central-1` | Your preferred AWS region |
| `TF_STATE_BUCKET` | `my-company-terraform-state` | From Step 1 |
| `TF_STATE_LOCK_TABLE` | `terraform-state-lock` | From Step 1 |

## Step 3: Configure Environments (2 minutes)

Set up environment protection:

**Settings > Environments > New environment**

Create three environments:

1. **dev**
   - No protection rules (for testing)

2. **staging**
   - Add 1 required reviewer
   - Select reviewers from your team

3. **prod**
   - Add 2 required reviewers
   - Enable deployment branches: `main` only
   - Optional: Add 5-minute wait timer

## Step 4: Run Infrastructure Deployment (20 minutes)

### First Deployment (Plan)

1. Go to **Actions** tab
2. Select **Deploy Infrastructure** workflow
3. Click **Run workflow**
4. Configure:
   - Environment: `dev`
   - Terraform action: `plan`
   - Auto-approve: `false`
5. Click **Run workflow**

Review the plan output to ensure it looks correct.

### Apply Infrastructure

1. Go to **Actions** tab
2. Select **Deploy Infrastructure** workflow
3. Click **Run workflow**
4. Configure:
   - Environment: `dev`
   - Terraform action: `apply`
   - Auto-approve: `true`
5. Click **Run workflow**

Wait 15-20 minutes for:
- VPC and networking creation
- EKS cluster provisioning
- Node group launch
- kubectl configuration

## Step 5: Verify Deployment (2 minutes)

After the workflow completes:

### Check Workflow Summary

Review the deployment summary in the workflow run:
- All jobs should show green checkmarks
- Note the cluster name and ECR URL in outputs

### Verify Locally

```bash
# Configure kubectl
aws eks update-kubeconfig --name locust-eks-dev --region eu-central-1

# Check cluster
kubectl cluster-info
kubectl get nodes

# Verify namespaces
kubectl get namespaces
```

## What's Next?

Your infrastructure is now ready! Next steps:

### 1. Build and Deploy Application

```bash
# Get ECR URL from workflow outputs
ECR_URL="123456789.dkr.ecr.eu-central-1.amazonaws.com/locust"

# Authenticate Docker to ECR
aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin ${ECR_URL}

# Build and push
docker build -t ${ECR_URL}:latest -f docker/Dockerfile .
docker push ${ECR_URL}:latest
```

### 2. Deploy Locust to Kubernetes

```bash
# Apply Kubernetes manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/master-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/service.yaml
```

### 3. Access Locust Web UI

```bash
# Get LoadBalancer URL
kubectl get svc locust-master -n locust

# Or use port-forward for immediate access
kubectl port-forward -n locust svc/locust-master 8089:8089
```

Open http://localhost:8089 in your browser.

## Common Commands

### View Workflow Runs

```bash
# List recent workflow runs
gh run list --workflow=deploy-infrastructure.yml

# View specific run
gh run view <run-id>

# View logs
gh run view <run-id> --log
```

### Manage Infrastructure

```bash
# Get cluster info
aws eks describe-cluster --name locust-eks-dev --region eu-central-1

# List nodes
kubectl get nodes -o wide

# View all resources
kubectl get all -n locust
```

### Destroy Infrastructure (When Done)

1. Go to **Actions** tab
2. Select **Deploy Infrastructure** workflow
3. Click **Run workflow**
4. Configure:
   - Environment: `dev`
   - Terraform action: `destroy`
   - Auto-approve: `true`
5. Click **Run workflow**

## Troubleshooting

### Issue: Workflow fails at "Validate AWS Credentials"

**Solution**: Check that AWS secrets are set correctly
```bash
# Test locally
aws sts get-caller-identity
```

### Issue: "Backend initialization failed"

**Solution**: Verify S3 bucket exists
```bash
aws s3 ls s3://my-company-terraform-state
```

### Issue: "State lock error"

**Solution**: Wait for other operations to complete, or force unlock
```bash
cd terraform
terraform force-unlock <lock-id>
```

### Issue: "Nodes not ready"

**Solution**: Check EC2 instances in AWS Console
```bash
# View node status
kubectl get nodes
kubectl describe nodes

# Check events
kubectl get events -n kube-system
```

## Cost Estimate

Running this infrastructure 24/7:

| Resource | Monthly Cost |
|----------|--------------|
| EKS Control Plane | $73 |
| 2x t3.medium nodes | $60 |
| 2x NAT Gateways | $65 |
| CloudWatch Logs | $10 |
| **Total** | **~$208/month** |

**Pro tip**: Destroy dev environment when not in use to save ~$200/month!

## Support

Need help?

1. Check the detailed guides:
   - `.github/GITHUB_ACTIONS_SETUP.md` - Complete setup guide
   - `.github/SECRETS_SETUP.md` - Secrets configuration
   - `.github/WORKFLOW_ARCHITECTURE.md` - Architecture details

2. Review workflow logs:
   - Actions > Workflow run > View logs

3. Check AWS resources:
   - CloudWatch Logs
   - EC2 Console (for node status)
   - EKS Console (for cluster details)

4. Open an issue in the repository

## Success Checklist

After deployment, verify:

- [ ] Workflow completed successfully (all jobs green)
- [ ] S3 bucket contains Terraform state
- [ ] EKS cluster is visible in AWS Console
- [ ] `kubectl get nodes` shows ready nodes
- [ ] ECR repository exists
- [ ] CloudWatch log groups are created

Congratulations! Your infrastructure is ready for Locust deployment!
