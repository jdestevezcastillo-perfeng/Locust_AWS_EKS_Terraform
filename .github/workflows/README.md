# GitHub Actions Workflows

This directory contains GitHub Actions workflows for automating the deployment of the Locust load testing infrastructure and application on AWS EKS.

## Table of Contents

- [Workflows Overview](#workflows-overview)
- [Prerequisites](#prerequisites)
- [GitHub Secrets Configuration](#github-secrets-configuration)
- [Workflow Usage](#workflow-usage)
- [Composite Actions](#composite-actions)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Workflows Overview

### 1. Deploy Application Workflow (`deploy-application.yml`)

**Purpose**: Builds Docker images, pushes them to Amazon ECR, and deploys the Locust application to Kubernetes.

**Key Features**:
- Multi-stage deployment with validation, build, deploy, and verification
- Automatic image tagging with environment, git SHA, and timestamp
- Container security scanning with Trivy
- Health checks and deployment verification
- LoadBalancer provisioning and endpoint discovery
- Comprehensive deployment summaries and artifacts
- Support for multiple environments (dev, staging, prod)

**Trigger Methods**:
1. Manual trigger via GitHub UI (workflow_dispatch)
2. Called by other workflows (workflow_call)

**Jobs**:
1. **validate**: Validates prerequisites and retrieves infrastructure details
2. **build-push**: Builds and pushes Docker image to ECR with security scanning
3. **deploy-kubernetes**: Deploys application to Kubernetes cluster
4. **verify-deployment**: Post-deployment verification and health checks
5. **notify**: Sends notifications and creates deployment summary

## Prerequisites

Before using these workflows, ensure you have:

1. **AWS Infrastructure Deployed**:
   - EKS cluster must be created
   - ECR repository must exist
   - Terraform state must be initialized and contain infrastructure outputs

2. **GitHub Repository Secrets Configured** (see next section)

3. **Kubernetes Manifests**: Located in `/kubernetes/base/`
   - namespace.yaml
   - configmap.yaml
   - master-deployment.yaml
   - master-service.yaml
   - worker-deployment.yaml
   - worker-hpa.yaml

## GitHub Secrets Configuration

Configure the following secrets in your GitHub repository:

### Required Secrets

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |

### Optional Secrets

| Secret Name | Description | Default | Example |
|-------------|-------------|---------|---------|
| `AWS_REGION` | AWS region for deployment | `eu-central-1` | `us-west-2` |
| `ECR_REPOSITORY_URL` | ECR repository URL (auto-retrieved if not set) | From Terraform | `123456789.dkr.ecr.eu-central-1.amazonaws.com/locust-load-tests` |
| `EKS_CLUSTER_NAME` | EKS cluster name (auto-retrieved if not set) | From Terraform | `locust-eks-dev` |

### Configuring Secrets

1. Navigate to your GitHub repository
2. Go to **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Add each secret with the appropriate name and value

### IAM Permissions Required

The AWS IAM user/role must have permissions for:
- **ECR**: Push/pull images, authenticate
- **EKS**: Describe cluster, update kubeconfig
- **STS**: Get caller identity
- **S3**: Access Terraform state (if using remote backend)

Example IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Workflow Usage

### Deploy Application Workflow

#### Manual Deployment via GitHub UI

1. Navigate to **Actions** tab in GitHub repository
2. Select **Deploy Locust Application** workflow
3. Click **Run workflow**
4. Configure parameters:
   - **Environment**: Select target environment (dev, staging, prod)
   - **Image Tag**: Leave empty for auto-generated tag or specify custom tag
   - **Skip Tests**: Check to skip post-deployment verification
5. Click **Run workflow**

#### Workflow Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `environment` | choice | Yes | `dev` | Deployment environment (dev/staging/prod) |
| `image_tag` | string | No | Auto-generated | Docker image tag |
| `skip_tests` | boolean | No | `false` | Skip post-deployment tests |

#### Auto-generated Image Tags

When `image_tag` is not specified, the workflow generates tags in the format:
```
{environment}-{git-sha}-{timestamp}
```

Example: `dev-a3f2c1b-20250109-143022`

#### Calling from Another Workflow

```yaml
name: CI/CD Pipeline
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: ./.github/workflows/deploy-application.yml
    with:
      environment: 'prod'
      image_tag: 'v1.2.3'
      skip_tests: false
    secrets:
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: ${{ secrets.AWS_REGION }}
```

### Workflow Outputs and Artifacts

Each workflow run produces several artifacts:

1. **Image Metadata** (`image-metadata.json`):
   - Image URI and tag
   - Git commit information
   - Build timestamp
   - Built by information

2. **Deployment Summary** (`deployment-summary.md`):
   - Environment and cluster details
   - Kubernetes resource status
   - Access URLs and commands
   - Quick reference commands

3. **Verification Report** (`verification-report.md`):
   - Pod and deployment status
   - Service endpoints
   - Recent events
   - Resource usage

4. **Security Scan Results** (SARIF format):
   - Container vulnerability scan
   - Uploaded to GitHub Security tab

### Monitoring Workflow Execution

#### View Progress

1. Navigate to **Actions** tab
2. Click on the running workflow
3. Monitor each job's progress in real-time

#### View Logs

- Click on any job to see detailed logs
- Expand steps to see command output
- Download logs for offline analysis

#### View Deployment Summary

After successful deployment, check the **Summary** tab for:
- Deployment details
- Access information
- Quick commands

## Composite Actions

### Setup Prerequisites Action

**Location**: `.github/actions/setup-prerequisites/action.yml`

**Purpose**: Validates and configures required tools for AWS EKS deployment.

**What it does**:
1. Sets up Terraform with specified version
2. Verifies AWS CLI installation
3. Configures AWS credentials
4. Validates IAM permissions
5. Installs and configures kubectl
6. Verifies Docker installation
7. Validates project structure
8. Caches Terraform plugins

**Inputs**:
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `aws-region` | Yes | `eu-central-1` | AWS region |
| `terraform-version` | No | `1.9.0` | Terraform version |
| `kubectl-version` | No | `1.31.0` | kubectl version |

**Outputs**:
| Output | Description |
|--------|-------------|
| `terraform-version` | Installed Terraform version |
| `aws-cli-version` | Installed AWS CLI version |
| `kubectl-version` | Installed kubectl version |
| `aws-account-id` | AWS account ID |
| `aws-user` | AWS user/role name |
| `validation-status` | Overall validation status |

**Usage**:
```yaml
- name: Setup Prerequisites
  uses: ./.github/actions/setup-prerequisites
  with:
    aws-region: 'eu-central-1'
    terraform-version: '1.9.0'
    kubectl-version: '1.31.0'
```

## Best Practices

### 1. Environment Strategy

- **Dev**: Use for development and testing
  - Auto-deploy on feature branches
  - Lower resource limits
  - Shorter retention periods

- **Staging**: Pre-production testing
  - Deploy from release branches
  - Production-like configuration
  - Extended testing

- **Prod**: Production environment
  - Deploy from main/master only
  - Require manual approval
  - Full monitoring and alerting

### 2. Image Tagging Strategy

- Use semantic versioning for releases: `v1.2.3`
- Use auto-generated tags for CI/CD: `env-sha-timestamp`
- Always maintain `latest` and `{env}-latest` tags
- Tag production releases: `prod-v1.2.3`

### 3. Security Best Practices

- Rotate AWS credentials regularly
- Use IAM roles with least privilege
- Review security scan results before deployment
- Monitor container vulnerabilities
- Keep base images updated

### 4. Cost Optimization

- Destroy dev/staging environments when not in use
- Use appropriate instance types
- Configure HPA with appropriate thresholds
- Monitor resource usage
- Set pod resource limits

### 5. Deployment Safety

- Always test in dev/staging first
- Use manual approval for production
- Monitor deployments in real-time
- Have rollback procedures ready
- Maintain deployment documentation

## Troubleshooting

### Common Issues and Solutions

#### 1. Terraform State Not Found

**Error**: `Terraform state is empty or not initialized`

**Solution**:
- Ensure infrastructure is deployed first
- Verify Terraform state exists: `cd terraform && terraform state list`
- If using remote backend, verify S3 bucket access

#### 2. ECR Authentication Failed

**Error**: `Failed to authenticate with ECR`

**Solution**:
- Verify AWS credentials are valid
- Check IAM permissions for ECR
- Ensure AWS region is correct
- Try manual ECR login: `aws ecr get-login-password --region {region}`

#### 3. kubectl Connection Failed

**Error**: `kubectl not connected to cluster`

**Solution**:
- Verify EKS cluster exists
- Check AWS credentials and region
- Manually update kubeconfig: `aws eks update-kubeconfig --name {cluster}`
- Verify cluster status in AWS console

#### 4. Image Push Failed

**Error**: `Failed to push image`

**Solution**:
- Verify ECR repository exists
- Check network connectivity
- Ensure sufficient disk space
- Retry the workflow

#### 5. Pod Not Ready

**Error**: `Pods failed to become ready`

**Solution**:
- Check pod logs: `kubectl logs -n locust deployment/locust-master`
- Verify image can be pulled: `kubectl describe pod -n locust {pod-name}`
- Check resource limits and node capacity
- Verify ConfigMap and secrets exist

#### 6. LoadBalancer Not Provisioned

**Warning**: `LoadBalancer IP not yet assigned`

**Solution**:
- Wait 2-5 minutes for AWS to provision
- Check service status: `kubectl get svc locust-master -n locust`
- Verify VPC and subnet configuration
- Use port-forward as temporary workaround:
  ```bash
  kubectl port-forward -n locust svc/locust-master 8089:8089
  ```

#### 7. HPA Not Scaling

**Issue**: Workers not auto-scaling

**Solution**:
- Verify metrics-server is installed
- Check HPA status: `kubectl get hpa -n locust`
- Review HPA metrics: `kubectl describe hpa -n locust`
- Verify CPU utilization is above threshold
- Check pod resource requests are set

### Debug Commands

```bash
# View workflow logs locally
gh run view {run-id} --log

# Get deployment status
kubectl get all -n locust

# View recent events
kubectl get events -n locust --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -f deployment/locust-master -n locust
kubectl logs -f deployment/locust-worker -n locust

# Debug pod issues
kubectl describe pod -n locust {pod-name}

# Test service connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://locust-master.locust.svc.cluster.local:8089

# Access Locust UI via port-forward
kubectl port-forward -n locust svc/locust-master 8089:8089
```

### Getting Help

1. **Check Workflow Logs**: Detailed logs in GitHub Actions
2. **Review Deployment Summary**: Artifacts contain useful debug info
3. **Kubernetes Events**: `kubectl get events -n locust`
4. **AWS Console**: Verify EKS, ECR, and networking
5. **GitHub Discussions**: Ask questions in repository discussions
6. **Documentation**: Review project README and AWS_SETUP.md

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Terraform Documentation](https://www.terraform.io/docs/)

## Workflow Maintenance

### Updating Workflows

1. Create feature branch
2. Modify workflow files
3. Test in dev environment
4. Create pull request
5. Review and merge

### Version Management

- Keep tool versions specified in composite action
- Test new versions in dev first
- Update documentation when changing versions
- Use dependabot for action version updates

### Monitoring

- Review workflow run history regularly
- Monitor success/failure rates
- Track deployment duration
- Analyze artifact sizes
- Review security scan results

---

**Last Updated**: 2025-01-09
**Maintained By**: Platform Engineering Team
