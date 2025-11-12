# Development defaults – smallest footprint and permissive networking
aws_region  = "eu-central-1"
environment = "dev"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

cluster_name                         = "locust-dev-cluster"
kubernetes_version                   = "1.28"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]  # Overridden during deploy for safety

node_group_name    = "locust-dev-nodes"
node_instance_type = "t3.small"
node_capacity_type = "SPOT"
node_disk_size     = 20
desired_capacity   = 3
min_capacity       = 3
max_capacity       = 10

ecr_repository_name = "locust-dev-load-tests"
ecr_scan_on_push    = false

log_retention_days = 7
