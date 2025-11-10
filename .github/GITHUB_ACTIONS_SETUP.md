# GitHub Actions Setup Guide

This guide explains how to configure and use the GitHub Actions workflows for deploying the Locust load testing infrastructure on AWS EKS.

## Overview

The deployment system consists of:

1. **Composite Action**: `.github/actions/setup-prerequisites/action.yml`
   - Reusable action for validating and configuring prerequisites
   - Handles Terraform, AWS CLI, kubectl, Docker, and jq verification
   - Validates AWS credentials and permissions

2. **Infrastructure Workflow**: `.github/workflows/deploy-infrastructure.yml`
   - Manages complete infrastructure lifecycle (plan/apply/destroy)
   - Integrates with Terraform S3 backend for state management
   - Configures kubectl access to the EKS cluster
   - Supports multiple environments (dev/staging/prod)

## Prerequisites

### 1. AWS Account Setup

Before running the workflows, ensure you have:

- An AWS account with appropriate permissions
- IAM user or role with permissions for:
  - EKS cluster creation and management
  - VPC and networking resources
  - ECR repository management
  - IAM role creation
  - CloudWatch logs
  - S3 and DynamoDB (for Terraform state)

### 2. Terraform State Backend

The workflows use an S3 backend for Terraform state management. You need to create:

#### S3 Bucket for State Storage

```bash
aws s3 mb s3://your-terraform-state-bucket --region eu-central-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket your-terraform-state-bucket \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

#### DynamoDB Table for State Locking

```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-central-1
```

## GitHub Configuration

### Required Secrets

Configure the following secrets in your GitHub repository:

**Settings > Secrets and variables > Actions > New repository secret**

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key for deployment | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | Default AWS region | `eu-central-1` |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state | `your-terraform-state-bucket` |
| `TF_STATE_LOCK_TABLE` | DynamoDB table for state locking | `terraform-state-lock` |

**Optional Secrets:**

| Secret Name | Description |
|-------------|-------------|
| `AWS_SESSION_TOKEN` | Required if using temporary credentials/assumed roles |

### Environment Protection Rules (Recommended)

For production deployments, configure environment protection:

1. Go to **Settings > Environments**
2. Create environments: `dev`, `staging`, `prod`
3. For `prod`, configure:
   - **Required reviewers**: Add team members who must approve
   - **Wait timer**: Optional delay before deployment
   - **Deployment branches**: Limit to `main` branch only

## IAM Policy for GitHub Actions

Create an IAM policy with the following minimum permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateManagement",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-terraform-state-bucket",
        "arn:aws:s3:::your-terraform-state-bucket/*"
      ]
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    },
    {
      "Sid": "EKSClusterManagement",
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "iam:CreateServiceLinkedRole",
        "iam:CreatePolicy",
        "iam:CreateRole",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:DeleteRole",
        "iam:DeleteRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:PassRole",
        "logs:*",
        "cloudwatch:*",
        "ecr:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### 1. Running Terraform Plan

To preview infrastructure changes:

1. Go to **Actions** tab in GitHub
2. Select **Deploy Infrastructure** workflow
3. Click **Run workflow**
4. Configure:
   - **Environment**: `dev` (or `staging`/`prod`)
   - **Terraform action**: `plan`
   - **Auto-approve**: `false`
5. Click **Run workflow**

The workflow will:
- Validate prerequisites
- Initialize Terraform
- Generate and display a plan
- Upload the plan as an artifact (valid for 5 days)

### 2. Applying Infrastructure

To deploy the infrastructure:

1. Go to **Actions** tab
2. Select **Deploy Infrastructure** workflow
3. Click **Run workflow**
4. Configure:
   - **Environment**: Select target environment
   - **Terraform action**: `apply`
   - **Auto-approve**: `true` (required for workflow execution)
5. Click **Run workflow**

The workflow will:
- Validate prerequisites
- Apply Terraform changes
- Configure kubectl to access the cluster
- Display cluster information and next steps

**Important**: For production, environment protection rules will require approval before deployment proceeds.

### 3. Destroying Infrastructure

To clean up all resources:

1. Go to **Actions** tab
2. Select **Deploy Infrastructure** workflow
3. Click **Run workflow**
4. Configure:
   - **Environment**: Select environment to destroy
   - **Terraform action**: `destroy`
   - **Auto-approve**: `true`
5. Click **Run workflow**

**Warning**: This will permanently delete all infrastructure resources in the selected environment.

## Workflow Outputs

After successful deployment, the workflow provides:

### Job Outputs

The `apply-infrastructure` job exports:
- `cluster-name`: EKS cluster name
- `cluster-endpoint`: Kubernetes API endpoint
- `ecr-url`: ECR repository URL
- `aws-region`: Deployment region

### Artifacts

- **terraform-plan-{environment}**: Terraform plan file (5 day retention)
- **deployment-env-{environment}**: Environment variables file (30 day retention)

### Accessing Outputs

To use these outputs in subsequent workflows:

```yaml
jobs:
  deploy-app:
    needs: infrastructure  # depends on the infrastructure job
    runs-on: ubuntu-latest
    steps:
      - name: Use Infrastructure Outputs
        run: |
          echo "Cluster: ${{ needs.infrastructure.outputs.cluster-name }}"
          echo "ECR: ${{ needs.infrastructure.outputs.ecr-url }}"
```

## Environment-Specific Configuration

### Using Environment Variables

The workflow automatically sets environment-specific variables:

```bash
export TF_VAR_environment="dev"  # or staging/prod
export TF_VAR_aws_region="eu-central-1"
```

### Custom Terraform Variables

To pass custom variables, modify the workflow:

```yaml
- name: Terraform Apply
  env:
    TF_VAR_cluster_name: "my-custom-cluster"
    TF_VAR_desired_capacity: "3"
  run: terraform apply -auto-approve
```

## Local Testing

To test the deployment locally before running in GitHub Actions:

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="eu-central-1"
export TF_VAR_environment="dev"

# Run the prerequisite checks (manual simulation)
terraform version
aws --version
kubectl version --client
docker --version
jq --version

# Validate AWS credentials
aws sts get-caller-identity

# Initialize and plan Terraform
cd terraform
terraform init \
  -backend-config="bucket=your-terraform-state-bucket" \
  -backend-config="key=locust-eks/dev/terraform.tfstate" \
  -backend-config="region=eu-central-1" \
  -backend-config="dynamodb_table=terraform-state-lock"

terraform plan -out=tfplan

# Apply if plan looks good
terraform apply tfplan
```

## Troubleshooting

### Common Issues

#### 1. "Backend initialization required"

**Solution**: The workflow automatically initializes the backend. If you see this error, check that:
- `TF_STATE_BUCKET` secret is set correctly
- S3 bucket exists and is accessible
- IAM permissions include S3 access

#### 2. "Error acquiring state lock"

**Solution**:
- Another process might be running Terraform
- Check DynamoDB table for stale locks
- Wait for other operations to complete
- Force unlock (use with caution): `terraform force-unlock <lock-id>`

#### 3. "Cluster nodes not ready"

**Solution**:
- EKS node provisioning can take 5-10 minutes
- The workflow waits up to 5 minutes automatically
- Check AWS Console for EC2 instance status
- Review CloudWatch logs for node group errors

#### 4. "Insufficient IAM permissions"

**Solution**:
- Review the IAM policy section above
- Ensure the IAM user/role has all required permissions
- Check for service control policies (SCPs) that might restrict actions

### Debug Mode

To enable detailed logging, add to the workflow:

```yaml
env:
  TF_LOG: DEBUG
  TF_LOG_PATH: ./terraform.log
```

## Security Best Practices

1. **Least Privilege**: Grant only the minimum required IAM permissions
2. **Secrets Rotation**: Regularly rotate AWS access keys
3. **Environment Isolation**: Use separate AWS accounts or strict tagging for different environments
4. **State Encryption**: Always enable S3 bucket encryption for Terraform state
5. **Audit Logging**: Enable CloudTrail to audit all AWS API calls
6. **Branch Protection**: Require PR reviews before merging infrastructure changes
7. **Environment Protection**: Require manual approval for production deployments

## Cost Management

### Cost Optimization Tips

1. **Destroy Dev Resources**: Run destroy workflow when not actively testing
2. **Use Spot Instances**: Consider spot instances for non-production workloads
3. **Right-Size Nodes**: Adjust node types based on actual usage
4. **Monitor Costs**: Set up AWS Budget alerts
5. **Review NAT Gateways**: These are expensive (~$32/month each); consider alternatives for dev

### Estimated Costs

Based on the Terraform outputs:
- **EKS Control Plane**: ~$73/month (fixed)
- **Worker Nodes**: ~$30/month per t3.medium node
- **NAT Gateways**: ~$65/month (2 gateways)
- **CloudWatch Logs**: ~$5-15/month (variable)

**Total for dev environment with 2 nodes**: ~$200/month if running 24/7

**Cost-saving strategy**: Destroy dev/staging when not in use!

## Next Steps

After infrastructure deployment:

1. **Build Docker Image**: Build and push the Locust container to ECR
2. **Deploy to Kubernetes**: Deploy Locust master and workers
3. **Configure Load Balancer**: Access the Locust web UI
4. **Set up Monitoring**: Configure Prometheus and Grafana for metrics

See the main project README for application deployment steps.

## Support and Contribution

For issues or questions:
- Review workflow logs in the Actions tab
- Check Terraform state in S3 bucket
- Review AWS CloudWatch logs for cluster issues
- Open an issue in the repository

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [kubectl Documentation](https://kubernetes.io/docs/reference/kubectl/)
