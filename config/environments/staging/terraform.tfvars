# Staging environment – mirrors production sizing without full scale
aws_region  = "us-east-1"
environment = "staging"

vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.20.0/24"]

cluster_name                         = "locust-staging-cluster"
kubernetes_version                   = "1.28"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]  # Replace with real office/VPN CIDR

node_group_name    = "locust-staging-nodes"
node_instance_type = "t3.medium"
node_capacity_type = "ON_DEMAND"
node_disk_size     = 40
desired_capacity   = 4
min_capacity       = 3
max_capacity       = 15

ecr_repository_name = "locust-staging-load-tests"
ecr_scan_on_push    = true

log_retention_days = 30
