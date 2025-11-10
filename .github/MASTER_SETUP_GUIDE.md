# GitHub Actions Setup Guide - Master Documentation

## Overview

This guide consolidates all setup information for the GitHub Actions-based deployment system for the Locust AWS EKS project.

## What Was Built

We've migrated from bash scripts (`deploy.sh`) to a comprehensive GitHub Actions workflow system with:

### 1. Reusable Components
- **Setup Prerequisites Composite Action** (`.github/actions/setup-prerequisites/action.yml`)
  - Validates and installs required tools
  - Configures AWS and kubectl
  - Used by all workflows

### 2. Individual Workflows
- **Infrastructure Deployment** (`.github/workflows/deploy-infrastructure.yml`)
  - Terraform infrastructure management
  - EKS cluster creation
  - ECR repository setup

- **Application Deployment** (`.github/workflows/deploy-application.yml`)
  - Docker image build and push
  - Kubernetes deployment
  - Health checks and verification

- **Monitoring Deployment** (`.github/workflows/deploy-monitoring.yml`)
  - Prometheus and Grafana setup
  - ServiceMonitors and alerting
  - Dashboard configuration

### 3. Orchestration
- **Complete Deployment** (`.github/workflows/deploy-complete.yml`)
  - End-to-end deployment orchestration
  - Flexible workflow with skip options
  - Comprehensive status reporting

## Quick Start (5 Steps)

### Step 1: Create AWS Backend Resources (5 minutes)

The workflows need an S3 bucket for Terraform state and DynamoDB for locking:

```bash
cd /home/lostborion/Documents/veeam-extended/.github
chmod +x setup-backend.sh
./setup-backend.sh
```

This creates:
- S3 bucket: `locust-terraform-state`
- DynamoDB table: `terraform-state-lock`

**Note the outputs** - you'll need them for GitHub Secrets!

### Step 2: Configure GitHub Secrets (3 minutes)

Go to your repository: **Settings → Secrets and variables → Actions → New repository secret**

Add these secrets:

| Secret Name | Description | Where to Get |
|-------------|-------------|--------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key | IAM Console → Security Credentials |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key | IAM Console → Security Credentials |
| `AWS_REGION` | Deployment region | `eu-central-1` (or your preference) |
| `TF_STATE_BUCKET` | S3 bucket name | Output from Step 1 |
| `TF_STATE_LOCK_TABLE` | DynamoDB table | Output from Step 1 |
| `GRAFANA_ADMIN_PASSWORD` | Grafana password | Choose a strong password |

### Step 3: Set Up Environments (Optional but Recommended)

Go to **Settings → Environments** and create:

| Environment | Protection Rules |
|-------------|------------------|
| `dev` | None (for quick testing) |
| `staging` | 1 required reviewer |
| `prod` | 2 required reviewers + branch restriction (main only) |

### Step 4: Test Infrastructure Deployment (20 minutes)

1. Go to **Actions** tab
2. Select **Deploy Infrastructure**
3. Click **Run workflow**
4. Configure:
   - Environment: `dev`
   - Terraform action: `apply`
   - Auto-approve: `true`
5. Click **Run workflow**

Wait ~20 minutes for EKS cluster creation.

### Step 5: Run Complete Deployment (10 minutes)

1. Go to **Actions** tab
2. Select **Complete Deployment**
3. Click **Run workflow**
4. Configure:
   - Environment: `dev`
   - Terraform action: `apply`
   - Auto-approve: `true`
   - Deploy application: `true`
   - Skip monitoring: `false`
5. Click **Run workflow**

This will:
- Deploy application to existing infrastructure
- Set up monitoring
- Provide access URLs in the summary

## Detailed Documentation

Each component has detailed documentation:

### Infrastructure & Prerequisites
- **Complete Setup Guide**: `.github/GITHUB_ACTIONS_SETUP.md`
- **Secrets Configuration**: `.github/SECRETS_SETUP.md`
- **Architecture Details**: `.github/WORKFLOW_ARCHITECTURE.md`
- **Quick Start**: `.github/QUICK_START.md`

### Application Deployment
- **Workflow Guide**: `.github/workflows/README.md`
- **Quick Reference**: `.github/QUICKSTART.md`

### Monitoring & Observability
- **Best Practices**: `docs/MONITORING_BEST_PRACTICES.md`
- **Deployment Summary**: `MONITORING_DEPLOYMENT_SUMMARY.md`
- **Quick Reference**: `.github/MONITORING_QUICK_REFERENCE.md`

## Workflow Usage Patterns

### Pattern 1: Full Deployment (New Environment)

Use the **Complete Deployment** workflow:

```
Actions → Complete Deployment → Run workflow
- Environment: dev
- Terraform action: apply
- Auto-approve: true
- Skip infrastructure: false
- Skip monitoring: false
- Deploy application: true
```

**Duration**: ~35-40 minutes
**Creates**: Full environment with infrastructure, application, and monitoring

### Pattern 2: Application Update Only

Use the **Application Deployment** workflow:

```
Actions → Deploy Locust Application → Run workflow
- Environment: dev
- Image tag: v1.2.3 (or leave empty for auto-generated)
```

**Duration**: ~15-20 minutes
**Updates**: Application code and containers only

### Pattern 3: Infrastructure Changes Only

Use the **Infrastructure Deployment** workflow:

```
Actions → Deploy Infrastructure → Run workflow
- Environment: dev
- Terraform action: plan (preview first)
- Auto-approve: false

Then if plan looks good:
- Terraform action: apply
- Auto-approve: true
```

**Duration**: ~20-25 minutes
**Changes**: AWS infrastructure only

### Pattern 4: Monitoring Setup/Update

Use the **Monitoring Deployment** workflow:

```
Actions → Deploy Monitoring → Run workflow
- Cluster name: (leave empty for auto-detect)
- AWS region: eu-central-1
```

**Duration**: ~10-15 minutes
**Updates**: Prometheus, Grafana, dashboards, alerts

## Required IAM Permissions

Your AWS IAM user/role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "ecr:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:GetRole",
        "iam:PassRole",
        "iam:ListAttachedRolePolicies",
        "logs:*",
        "autoscaling:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::locust-terraform-state",
        "arn:aws:s3:::locust-terraform-state/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    }
  ]
}
```

## Accessing Deployed Services

### Locust Web UI

After successful application deployment:

**Option 1: LoadBalancer (if available)**
```bash
# Get the URL from workflow summary or:
kubectl get svc locust-master -n locust -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Access: http://<hostname>:8089
```

**Option 2: Port Forward (always works)**
```bash
kubectl port-forward -n locust svc/locust-master 8089:8089
# Access: http://localhost:8089
```

### Grafana Dashboards

After successful monitoring deployment:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Access: http://localhost:3000
# Username: admin
# Password: (from GRAFANA_ADMIN_PASSWORD secret)
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Access: http://localhost:9090
```

## Troubleshooting

### Workflow Fails with "Terraform backend not initialized"

**Solution**: Run the backend setup script:
```bash
cd .github
./setup-backend.sh
```

### Workflow Fails with "AWS credentials not configured"

**Solution**: Check GitHub Secrets are set:
```bash
# In GitHub UI: Settings → Secrets → Actions
# Verify: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
```

### Terraform State Lock Error

**Symptoms**: Error message about state lock
**Solution**:
```bash
# Get lock ID from error message
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"locust-terraform-state/dev/terraform.tfstate"}}'
```

### Application Deployment Fails with "Cluster not found"

**Solution**: Deploy infrastructure first:
```bash
# Run Infrastructure Deployment workflow with action: apply
```

### Monitoring Deployment Can't Find Cluster

**Solution**: Ensure cluster is running and specify cluster name manually:
```bash
# Get cluster name
terraform -chdir=terraform output cluster_name

# Use that in workflow input
```

### LoadBalancer Takes Too Long

**Normal**: LoadBalancer provisioning can take 5-10 minutes
**Solution**: Use port-forward instead for immediate access

## Cost Management

### Estimated Monthly Costs (24/7 operation)

| Component | Cost/Month |
|-----------|------------|
| EKS Control Plane | $73 |
| Worker Nodes (2x t3.medium) | $60 |
| NAT Gateways (2x) | $65 |
| Monitoring Storage (50Gi) | $6 |
| CloudWatch Logs | $10 |
| **Total** | **~$214** |

### Cost-Saving Strategies

1. **Destroy dev/staging when not in use**
   ```bash
   # Actions → Deploy Infrastructure → destroy
   ```
   **Savings**: $200+/month per environment

2. **Use smaller instances for dev**
   ```bash
   # Edit terraform/variables.tf
   instance_type = "t3.small"  # $30/month instead of $60
   ```

3. **Reduce monitoring retention**
   ```bash
   # In workflow input:
   retention_days = 15  # Instead of 30
   ```

4. **Scale down workers when idle**
   ```bash
   kubectl scale deployment locust-worker --replicas=1 -n locust
   ```

## Security Best Practices

### 1. Use Environment Protection Rules
- Require approvals for production
- Restrict deployments to specific branches
- Add required reviewers

### 2. Rotate AWS Credentials Regularly
```bash
# Every 90 days:
# 1. Create new IAM access key
# 2. Update GitHub secrets
# 3. Delete old access key
```

### 3. Enable MFA for Production Environments
- Add MFA to AWS IAM user
- Require MFA for destructive operations

### 4. Review Terraform Plans
- Always run plan before apply
- Review changes in workflow logs
- Use environment approvals

### 5. Monitor Access Logs
- Enable CloudTrail
- Review GitHub Actions audit logs
- Set up alerts for suspicious activity

## Migration from deploy.sh

### What Changed

| Old (deploy.sh) | New (GitHub Actions) |
|-----------------|---------------------|
| Local execution | Cloud-based runners |
| Manual steps | Automated workflows |
| No state locking | DynamoDB locking |
| Local credentials | GitHub Secrets |
| No approval process | Environment protection |
| Manual validation | Automated health checks |
| Single script | Modular workflows |

### What Stayed the Same

- Same Terraform configuration
- Same Kubernetes manifests
- Same Docker images
- Same AWS resources

### Benefits of Migration

✅ **Automation**: No local setup required
✅ **Collaboration**: Team can deploy from GitHub UI
✅ **Audit Trail**: All deployments logged
✅ **Consistency**: Same environment every time
✅ **Safety**: Approval gates for production
✅ **Rollback**: Easy to revert via Git
✅ **Secrets Management**: Secure credential storage

## Next Steps

### Immediate (Today)
1. ✅ Complete Quick Start steps 1-5
2. ✅ Verify infrastructure deployed successfully
3. ✅ Access Locust UI and run test load test
4. ✅ Access Grafana and view dashboards

### Short-term (This Week)
1. Set up staging environment
2. Configure environment protection rules
3. Run production deployment with approvals
4. Document team runbook

### Medium-term (This Month)
1. Add custom Grafana dashboards
2. Configure AlertManager notifications (Slack/email)
3. Set up log aggregation
4. Implement automated testing

### Long-term (This Quarter)
1. Add distributed tracing (Jaeger)
2. Implement SLOs and error budgets
3. Set up disaster recovery
4. Add cost optimization automation

## Getting Help

### Documentation Resources
- **Infrastructure**: See `.github/GITHUB_ACTIONS_SETUP.md`
- **Application**: See `.github/workflows/README.md`
- **Monitoring**: See `docs/MONITORING_BEST_PRACTICES.md`

### Troubleshooting
1. Check workflow logs in GitHub Actions tab
2. Review job summaries for specific errors
3. Consult troubleshooting sections in individual docs
4. Check Kubernetes pod logs: `kubectl logs -n locust <pod-name>`

### Support Channels
- GitHub Issues for bugs
- Pull Requests for improvements
- Team documentation wiki

## Summary

You now have a complete GitHub Actions-based deployment system that:
- ✅ Automates infrastructure provisioning
- ✅ Builds and deploys applications
- ✅ Sets up comprehensive monitoring
- ✅ Provides safety through approvals
- ✅ Offers flexibility through modular workflows
- ✅ Scales from dev to production
- ✅ Includes extensive documentation

**Start with the Quick Start section above and you'll be running load tests in under 30 minutes!**
