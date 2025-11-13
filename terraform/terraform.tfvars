# AWS Region Configuration
aws_region  = "eu-central-1"
environment = "dev"

# VPC and Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

# EKS Cluster Configuration
cluster_name                           = "locust-dev-cluster"
kubernetes_version                     = "1.34"
cluster_endpoint_public_access         = true
cluster_endpoint_public_access_cidrs   = ["0.0.0.0/0"]  # Restrict to your IP in production

# EKS Node Group Configuration
node_group_name      = "locust-dev-nodes"
node_instance_type   = "t3.small"
node_capacity_type   = "SPOT"  # Using SPOT for cost savings (~70% discount)
node_disk_size       = 20
desired_capacity     = 3
min_capacity         = 3
max_capacity         = 10

# ECR Configuration
ecr_repository_name = "locust-dev-load-tests"
ecr_scan_on_push    = false  # Enable for security scanning (adds ~30s per push)

# CloudWatch Logging
log_retention_days = 7  # Increase for compliance requirements
