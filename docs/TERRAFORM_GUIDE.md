# Terraform Guide - EKS Cluster Setup

## What is Terraform?

Terraform is **Infrastructure as Code (IaC)**. Instead of clicking AWS console buttons, you write code that describes your infrastructure. Benefits:

- **Reproducible**: Same code = same infrastructure every time
- **Versionable**: Track infrastructure changes in git like code
- **Reusable**: Share infrastructure templates across teams
- **Automatable**: Deploy via CI/CD pipelines
- **Destroyable**: Clean up everything with one command

## Terraform Files You Now Have

```
main.tf              → Core infrastructure definition (VPC, EKS, Security Groups, IAM)
variables.tf         → Input variables with defaults
terraform.tfvars     → Actual values for those variables
outputs.tf           → Outputs to display after creation
```

## Quick Start Commands

### Step 1: Initialize Terraform

```bash
cd /home/lostborion/Documents/veeam
terraform init
```

**What it does:**
- Downloads AWS provider plugin
- Creates `.terraform/` directory (don't commit this)
- Prepares your working directory

**Output should show:**
```
Terraform has been successfully configured!
```

### Step 2: Review What Will Be Created

```bash
terraform plan
```

**What it does:**
- Shows you EXACTLY what will be created/modified
- No changes made yet (safe to review)
- Lists all resources with their configurations

**Look for:**
```
Plan: 15 to add, 0 to change, 0 to destroy.
```

### Step 3: Create Infrastructure (Takes 10-15 minutes)

```bash
terraform apply
```

**What it does:**
- Creates all AWS resources
- Saves state to `terraform.tfstate` (tracks what's deployed)
- Shows outputs (cluster details, ECR URL, etc.)

**You'll be asked:**
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

Type `yes` and hit Enter.

**Progress:**
```
aws_vpc.eks_vpc: Creating...
aws_eks_cluster.locust_cluster: Creating...
aws_eks_node_group.locust_nodes: Creating...
# ... (takes 10-15 minutes)

Apply complete! Resources: 15 added, 0 destroyed.

Outputs:

cluster_name = "locust-cluster"
cluster_endpoint = "https://ABC123.eu-central-1.eks.amazonaws.com"
ecr_repository_url = "649370233800.dkr.ecr.eu-central-1.amazonaws.com/locust-load-tests"
```

### Step 4: Update kubeconfig

After cluster is created, connect kubectl:

```bash
aws eks update-kubeconfig \
  --name locust-cluster \
  --region eu-central-1
```

Verify connection:
```bash
kubectl cluster-info
```

Should show your cluster endpoint.

## Understanding the Terraform Code

### main.tf Structure

```hcl
# 1. PROVIDER - Tells Terraform which cloud to use
provider "aws" {
  region = var.aws_region  # eu-central-1 (Frankfurt)
}

# 2. NETWORKING - VPC and subnets
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"  # Network range
  # ...
}

# 3. INTERNET ACCESS - So pods can reach external services
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

# 4. IAM ROLES - Permissions for cluster and nodes to access AWS
resource "aws_iam_role" "eks_cluster_role" {
  # Allows EKS service to manage cluster
}

resource "aws_iam_role" "node_group_role" {
  # Allows EC2 instances (nodes) to pull from ECR, access AWS
}

# 5. CLUSTER - The actual EKS cluster
resource "aws_eks_cluster" "locust_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  # ...
}

# 6. NODES - EC2 instances that run pods
resource "aws_eks_node_group" "locust_nodes" {
  cluster_name = aws_eks_cluster.locust_cluster.name
  desired_size = var.desired_capacity  # 3 t3.medium instances
}

# 7. CONTAINER REGISTRY - ECR for your Docker images
resource "aws_ecr_repository" "locust_repo" {
  name = "locust-load-tests"
}
```

### variables.tf - The Configuration

Think of these like function parameters:

```hcl
variable "aws_region" {
  default = "eu-central-1"  # Frankfurt
}

variable "desired_capacity" {
  default = 3  # Start with 3 nodes
}
```

These defaults can be overridden in `terraform.tfvars` or via CLI:

```bash
# Override during apply
terraform apply -var="desired_capacity=5"
```

### terraform.tfvars - Your Settings

```hcl
aws_region       = "eu-central-1"  # Frankfurt region
node_type        = "t3.medium"     # Instance type
desired_capacity = 3               # Start with 3 nodes
max_capacity     = 10              # Max 10 nodes (for autoscaling)
```

**Change these to customize deployment** (then run `terraform apply` again).

## Key Terraform Concepts

### State File (terraform.tfstate)

```bash
ls -la terraform.tfstate
```

**What it is:**
- JSON file tracking all deployed resources
- Maps your code to actual AWS resources
- Essential - without it, Terraform doesn't know what's deployed

**Important:**
- **NEVER edit manually**
- **NEVER commit to git** (contains secrets)
- Add to `.gitignore`:
  ```
  terraform.tfstate*
  .terraform/
  ```

### Resource Dependencies

Terraform automatically handles ordering:

```hcl
# This resource
resource "aws_eks_cluster" "locust_cluster" {
  role_arn = aws_iam_role.eks_cluster_role.arn  # Depends on IAM role
}

# Must be created AFTER the IAM role
resource "aws_iam_role" "eks_cluster_role" {
  # ...
}

# Terraform figures this out and creates IAM role first automatically
```

### Outputs

After `terraform apply`, displays important values:

```bash
# View outputs anytime
terraform output

# Get specific output
terraform output cluster_endpoint
terraform output ecr_repository_url
```

## Common Terraform Commands

```bash
# Initialize working directory
terraform init

# Validate syntax
terraform validate

# Format code nicely
terraform fmt

# Show what will change
terraform plan

# Apply changes to AWS
terraform apply

# Destroy all resources
terraform destroy

# Show current state
terraform show

# List resources in state
terraform state list

# View specific resource details
terraform state show aws_eks_cluster.locust_cluster

# Move state (advanced)
terraform state mv old_name new_name

# Refresh state from AWS (if resources changed outside Terraform)
terraform refresh
```

## Workflow Example

### Day 1: Create cluster

```bash
terraform init
terraform plan    # Review what will be created
terraform apply   # Create it (15 minutes)
```

### Day 2: Scale cluster to 5 nodes

```bash
# Edit terraform.tfvars
desired_capacity = 5

# Update
terraform plan    # Shows: modify aws_eks_node_group
terraform apply   # Adds 2 more nodes

# Check nodes
kubectl get nodes  # Now shows 5 nodes
```

### Day 3: Change instance type

```bash
# Edit terraform.tfvars
node_type = "t3.large"

# Update
terraform plan    # Shows: replace aws_eks_node_group
terraform apply   # Replaces nodes with larger instances
```

### Day N: Clean up everything

```bash
terraform destroy  # Deletes everything (ECR, EKS, VPC, etc.)
# Confirm with: yes
```

## Troubleshooting

### `terraform init` fails

```bash
Error: Failed to download providers
```

**Fix:**
```bash
# Check internet connection
# Or use proxy if behind firewall
terraform init -upgrade
```

### `terraform apply` hangs

Normal - EKS cluster creation takes 10-15 minutes. Let it run.

### `terraform destroy` won't delete ECR

ECR has images, Terraform can't delete non-empty repositories by default. Options:

1. Delete images manually in AWS console
2. Or modify main.tf:
   ```hcl
   resource "aws_ecr_repository" "locust_repo" {
     force_delete = true  # Auto-delete images
   }
   ```

### State file corrupted

```bash
# Refresh state from AWS
terraform refresh

# Or rebuild state (advanced, risky)
terraform state pull > backup.json
terraform state rm aws_resource_name
terraform import aws_resource_name resource-id
```

## Best Practices

1. **Always run `terraform plan` first** - Review before applying
2. **Keep state files safe** - Add to `.gitignore`, consider remote state
3. **Use meaningful variable values** - Clear defaults in variables.tf
4. **Tag resources** - Makes cleanup and billing easier
5. **Version your Terraform files** - Commit to git (just not state files)
6. **Document changes** - Add comments explaining "why" in code

## Next Steps

After cluster is created:

```bash
# 1. Update kubeconfig
aws eks update-kubeconfig --name locust-cluster --region eu-central-1

# 2. Verify connection
kubectl cluster-info

# 3. Push Docker image to ECR
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url)
docker build -t locust-load-tests .
docker tag locust-load-tests:latest $(terraform output -raw ecr_repository_url):latest
docker push $(terraform output -raw ecr_repository_url):latest

# 4. Deploy Kubernetes manifests
kubectl apply -f k8s-master-deployment.yaml
kubectl apply -f k8s-service.yaml
kubectl apply -f k8s-worker-deployment.yaml
```

## Learning Resources

- [Terraform Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Provider Reference](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [EKS on Terraform](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)

---

**Ready?** Run `terraform init` in the `/home/lostborion/Documents/veeam` directory!
