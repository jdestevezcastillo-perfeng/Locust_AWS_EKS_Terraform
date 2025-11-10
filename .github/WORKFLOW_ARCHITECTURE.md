# GitHub Actions Workflow Architecture

## Overview

This document describes the architecture and flow of the GitHub Actions workflows for deploying Locust on AWS EKS.

## Workflow Structure

```
.github/
├── actions/
│   └── setup-prerequisites/
│       └── action.yml                    # Reusable composite action
├── workflows/
│   ├── deploy-infrastructure.yml         # NEW: Infrastructure deployment
│   ├── deploy-application.yml            # Existing: Application deployment
│   └── deploy-monitoring.yml             # Existing: Monitoring setup
├── GITHUB_ACTIONS_SETUP.md              # Detailed setup guide
├── SECRETS_SETUP.md                     # Quick secrets reference
└── WORKFLOW_ARCHITECTURE.md             # This file
```

## Infrastructure Deployment Workflow

### Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   DEPLOY INFRASTRUCTURE WORKFLOW                 │
└─────────────────────────────────────────────────────────────────┘

Trigger: Manual (workflow_dispatch)
Inputs: environment, terraform-action, auto-approve

┌──────────────────────────────────────────────────────────────────┐
│ Job 1: validate-and-plan                                         │
│                                                                   │
│  1. Checkout repository                                          │
│  2. Setup prerequisites (composite action)                       │
│     ├─ Install/verify Terraform                                  │
│     ├─ Verify AWS CLI                                            │
│     ├─ Install/verify kubectl                                    │
│     ├─ Verify Docker                                             │
│     ├─ Verify jq                                                 │
│     ├─ Validate AWS credentials                                  │
│     ├─ Verify IAM permissions                                    │
│     └─ Cache Terraform plugins                                   │
│  3. Configure Terraform backend (S3 + DynamoDB)                  │
│  4. Terraform init                                               │
│  5. Terraform validate                                           │
│  6. Terraform plan                                               │
│  7. Upload plan artifact                                         │
│  8. Get current outputs (if exists)                              │
│                                                                   │
│  Outputs:                                                        │
│    - terraform-plan-exitcode                                     │
│    - cluster-name, ecr-url, aws-region                           │
│    - plan-summary                                                │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Job 2: apply-infrastructure (conditional)                        │
│                                                                   │
│  Condition: terraform-action == 'apply' || 'destroy'             │
│  Environment: dev/staging/prod (with protection rules)           │
│                                                                   │
│  1. Checkout repository                                          │
│  2. Setup prerequisites (composite action)                       │
│  3. Download Terraform plan artifact                             │
│  4. Configure Terraform backend                                  │
│  5. Terraform init                                               │
│  6. Terraform apply/destroy                                      │
│  7. Capture Terraform outputs                                    │
│  8. Upload deployment environment file                           │
│                                                                   │
│  Outputs:                                                        │
│    - cluster-name, cluster-endpoint                              │
│    - ecr-url, aws-region                                         │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Job 3: configure-kubectl (conditional)                           │
│                                                                   │
│  Condition: terraform-action == 'apply' && cluster exists        │
│                                                                   │
│  1. Checkout repository                                          │
│  2. Setup prerequisites (composite action)                       │
│  3. Update kubeconfig (aws eks update-kubeconfig)                │
│  4. Verify cluster connection                                    │
│  5. Wait for nodes to be ready                                   │
│  6. Display cluster status                                       │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Job 4: deployment-summary (always runs)                          │
│                                                                   │
│  1. Generate deployment summary                                  │
│  2. Display job statuses                                         │
│  3. Show infrastructure details                                  │
│  4. Provide next steps                                           │
│  5. Fail if deployment errors occurred                           │
└──────────────────────────────────────────────────────────────────┘
```

## Composite Action: Setup Prerequisites

### Purpose

Reusable action that validates and configures all required tools for deployment.

### Responsibilities

1. **Terraform Setup**
   - Install specific Terraform version
   - Verify installation
   - Cache plugins for performance

2. **AWS CLI Verification**
   - Verify AWS CLI v2 is installed (pre-installed on GitHub runners)
   - Configure AWS credentials
   - Validate credentials with `aws sts get-caller-identity`
   - Verify IAM permissions

3. **kubectl Setup**
   - Install specific kubectl version
   - Verify installation

4. **Tool Verification**
   - Docker (pre-installed on GitHub runners)
   - jq (pre-installed on GitHub runners)

5. **Project Validation**
   - Verify Terraform directory structure
   - Check for required configuration files

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `aws-region` | Yes | `eu-central-1` | AWS region for deployment |
| `terraform-version` | No | `1.9.0` | Terraform version |
| `kubectl-version` | No | `1.31.0` | kubectl version |

### Outputs

| Output | Description |
|--------|-------------|
| `terraform-version` | Installed Terraform version |
| `aws-cli-version` | Installed AWS CLI version |
| `kubectl-version` | Installed kubectl version |
| `aws-account-id` | AWS Account ID |
| `aws-user` | AWS User/Role |
| `validation-status` | Overall validation status |

## Terraform State Management

### Backend Configuration

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "locust-eks/{environment}/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### State Isolation

Different environments use different state files:
- **dev**: `locust-eks/dev/terraform.tfstate`
- **staging**: `locust-eks/staging/terraform.tfstate`
- **prod**: `locust-eks/prod/terraform.tfstate`

### State Locking

- DynamoDB table provides distributed locking
- Prevents concurrent modifications
- Automatically releases locks on completion

## Workflow Execution Modes

### 1. Plan Mode

**Purpose**: Preview infrastructure changes without applying them

**Configuration**:
```yaml
environment: dev
terraform-action: plan
auto-approve: false
```

**Behavior**:
- Runs validate-and-plan job only
- Generates and displays plan
- Uploads plan artifact (5-day retention)
- No infrastructure changes

### 2. Apply Mode

**Purpose**: Deploy infrastructure changes

**Configuration**:
```yaml
environment: dev
terraform-action: apply
auto-approve: true  # Required for workflow execution
```

**Behavior**:
- Runs all jobs sequentially
- Applies Terraform changes
- Configures kubectl access
- Provides deployment summary

**Protection**: Environment protection rules can require manual approval

### 3. Destroy Mode

**Purpose**: Clean up all infrastructure resources

**Configuration**:
```yaml
environment: dev
terraform-action: destroy
auto-approve: true  # Required
```

**Behavior**:
- Runs validate-and-plan and apply-infrastructure jobs
- Destroys all Terraform-managed resources
- Skips kubectl configuration (no cluster)

## Environment Protection

### Recommended Configuration

#### Development
- **Reviewers**: None
- **Wait timer**: 0 minutes
- **Deployment branches**: Any

#### Staging
- **Reviewers**: 1 team member
- **Wait timer**: 0 minutes
- **Deployment branches**: `main`, `develop`

#### Production
- **Reviewers**: 2 senior team members
- **Wait timer**: 5 minutes
- **Deployment branches**: `main` only

### Setup

1. Go to **Settings** > **Environments**
2. Click **New environment**
3. Enter environment name (`dev`, `staging`, `prod`)
4. Configure protection rules
5. Save

## Workflow Integration

### Dependency Chain

```
Infrastructure Workflow
    ↓
    ├─> Outputs: cluster-name, ecr-url, region
    ↓
Application Workflow (next step)
    ↓
    ├─> Build Docker image
    ├─> Push to ECR
    ├─> Deploy to Kubernetes
    ↓
Monitoring Workflow (final step)
    ↓
    └─> Deploy Prometheus, Grafana, etc.
```

### Using Infrastructure Outputs

The infrastructure workflow exports outputs that can be used by subsequent workflows:

```yaml
jobs:
  deploy-app:
    needs: infrastructure
    runs-on: ubuntu-latest
    steps:
      - name: Build and Push Image
        env:
          ECR_URL: ${{ needs.infrastructure.outputs.ecr-url }}
          CLUSTER_NAME: ${{ needs.infrastructure.outputs.cluster-name }}
        run: |
          # Build and push to ECR
          docker build -t ${ECR_URL}:latest .
          docker push ${ECR_URL}:latest
```

## Artifact Management

### Terraform Plan

- **Name**: `terraform-plan-{environment}`
- **Retention**: 5 days
- **Purpose**: Reuse plan between jobs, audit trail
- **Location**: Actions > Workflow run > Artifacts

### Deployment Environment

- **Name**: `deployment-env-{environment}`
- **Retention**: 30 days
- **Purpose**: Environment variables for subsequent deployments
- **Contents**:
  ```bash
  CLUSTER_NAME=locust-eks-dev
  CLUSTER_ENDPOINT=https://xxx.eks.amazonaws.com
  ECR_REPOSITORY_URL=123456789.dkr.ecr.eu-central-1.amazonaws.com/locust
  AWS_REGION=eu-central-1
  ```

## Error Handling

### Job Failures

Each job includes error handling:

1. **Validate & Plan**
   - Format check: `continue-on-error: true` (warning only)
   - Init/validate/plan: Hard failure stops workflow

2. **Apply Infrastructure**
   - Terraform errors: Stops workflow, preserves state lock
   - Auto-approve validation: Fails if not enabled

3. **Configure kubectl**
   - Connection timeout: 5 minutes with retries
   - Node readiness: 5 minutes with polling

4. **Deployment Summary**
   - Always runs (`if: always()`)
   - Reports status of all jobs
   - Fails if any deployment job failed

### State Lock Recovery

If a job fails mid-apply, the state lock might persist:

```bash
# List locks
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (use with caution)
cd terraform
terraform force-unlock <lock-id>
```

## Performance Optimizations

### Caching Strategy

1. **Terraform Plugins**
   ```yaml
   - uses: actions/cache@v4
     with:
       path: |
         ~/.terraform.d/plugin-cache
         terraform/.terraform
       key: ${{ runner.os }}-terraform-${{ hashFiles('terraform/.terraform.lock.hcl') }}
   ```

2. **Docker Layers** (for application workflow)
   - Multi-stage builds reduce image size
   - Layer caching via GitHub Actions cache

### Parallel Execution

Jobs run sequentially due to dependencies, but steps within jobs can be optimized:

- Multiple validation checks in parallel where possible
- Background processes for long-running operations

## Monitoring and Observability

### Workflow Metrics

Monitor these metrics:
- Workflow success/failure rate
- Average execution time per job
- Terraform plan changes frequency
- Environment deployment frequency

### Logging

All steps include detailed logging:
- Terraform output (human-readable)
- AWS CLI responses
- kubectl status checks
- Error messages with context

### Notifications

Consider adding:
- Slack notifications on deployment
- Email alerts on failures
- GitHub issue creation on repeated failures

## Security Considerations

### Secrets Management

1. **Required Secrets**
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `TF_STATE_BUCKET`
   - `TF_STATE_LOCK_TABLE`

2. **Optional Secrets**
   - `AWS_SESSION_TOKEN` (for temporary credentials)

3. **Best Practices**
   - Use environment-specific secrets
   - Rotate credentials regularly
   - Use IAM roles when possible
   - Enable MFA on IAM users

### Terraform State Security

1. **S3 Bucket**
   - Encryption at rest (AES256)
   - Versioning enabled
   - Public access blocked
   - Lifecycle policies for old versions

2. **DynamoDB Table**
   - Encrypted at rest
   - Pay-per-request billing (cost-effective)
   - No public access

### IAM Permissions

Follow principle of least privilege:
- Separate IAM users/roles per environment
- Use service control policies (SCPs) for guardrails
- Regular permission audits

## Cost Optimization

### Workflow Costs

GitHub Actions is free for public repositories, but be aware of:
- Minutes consumed per workflow run
- Storage for artifacts and caches

### Infrastructure Costs

The workflow helps manage costs by:
- Easy destroy workflow for non-production
- Clear cost estimates in Terraform outputs
- Environment-specific sizing

**Pro tip**: Destroy dev/staging environments when not in use!

```yaml
# Scheduled cleanup (example)
on:
  schedule:
    - cron: '0 19 * * 5'  # Every Friday at 7 PM
jobs:
  cleanup-dev:
    # Automatically destroy dev environment
```

## Troubleshooting Guide

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Backend init fails | Bucket doesn't exist | Create S3 bucket and DynamoDB table |
| State lock timeout | Previous run didn't complete | Force unlock or wait for timeout |
| IAM permission denied | Insufficient permissions | Review and update IAM policy |
| Cluster nodes not ready | EC2 launch issues | Check EC2 console and CloudWatch logs |
| kubectl connection fails | kubeconfig not updated | Re-run configure-kubectl job |

### Debug Mode

Enable verbose logging:

```yaml
env:
  TF_LOG: DEBUG
  AWS_SDK_LOAD_CONFIG: 1
```

## Future Enhancements

Potential improvements:

1. **Drift Detection**
   - Scheduled workflow to detect configuration drift
   - Compare actual infrastructure vs. Terraform state

2. **Cost Reporting**
   - Integrate with AWS Cost Explorer API
   - Report estimated vs. actual costs

3. **Automated Testing**
   - Run infrastructure tests (e.g., Terratest)
   - Validate security configurations

4. **Multi-Region Deployment**
   - Matrix strategy for multiple regions
   - Cross-region disaster recovery

5. **GitOps Integration**
   - ArgoCD or Flux for Kubernetes deployments
   - Automated sync from Git to cluster

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Composite Actions Guide](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action)
- [Terraform S3 Backend](https://www.terraform.io/docs/backends/types/s3.html)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [kubectl Reference](https://kubernetes.io/docs/reference/kubectl/)
