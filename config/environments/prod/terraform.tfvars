# Production environment – hardened defaults
aws_region  = "us-west-2"
environment = "prod"

vpc_cidr             = "10.20.0.0/16"
public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs = ["10.20.10.0/23", "10.20.12.0/23"]

cluster_name                         = "locust-prod-cluster"
kubernetes_version                   = "1.28"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["198.51.100.0/24"]  # Replace with corporate CIDR

node_group_name    = "locust-prod-nodes"
node_instance_type = "m5.large"
node_capacity_type = "ON_DEMAND"
node_disk_size     = 80
desired_capacity   = 6
min_capacity       = 4
max_capacity       = 25

ecr_repository_name = "locust-prod-load-tests"
ecr_scan_on_push    = true

log_retention_days = 90
