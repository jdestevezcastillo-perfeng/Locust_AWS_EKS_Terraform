# Production environment – hardened defaults
aws_region  = "us-west-2"
environment = "prod"

vpc_cidr             = "10.20.0.0/16"
public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs = ["10.20.10.0/23", "10.20.12.0/23"]

cluster_name                         = "locust-prod-cluster"
kubernetes_version                   = "1.34"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["198.51.100.0/24"]  # Replace with corporate CIDR

# EKS Locust Master Node Group Configuration
locust_master_node_group_name  = "locust-master-prod-nodes"
locust_master_instance_type    = "m5.large"          # Production-grade master
locust_master_capacity_type    = "ON_DEMAND"         # High availability, no spot
locust_master_disk_size        = 80
locust_master_desired_capacity = 1
locust_master_min_capacity     = 1
locust_master_max_capacity     = 2

# EKS Locust Worker Node Group Configuration
node_group_name      = "locust-worker-prod-nodes"
node_instance_type   = "c5.xlarge"       # High performance workers
node_capacity_type   = "ON_DEMAND"       # Production reliability
node_disk_size       = 80
desired_capacity     = 6
min_capacity         = 4
max_capacity         = 25

# EKS Monitoring Node Group Configuration
monitoring_node_group_name   = "monitoring-prod-nodes"
monitoring_instance_type     = "m5.xlarge"
monitoring_capacity_type     = "ON_DEMAND"       # Production monitoring needs reliability
monitoring_disk_size         = 100
monitoring_desired_capacity  = 3
monitoring_min_capacity      = 2
monitoring_max_capacity      = 6

ecr_repository_name = "locust-prod-load-tests"
ecr_scan_on_push    = true

log_retention_days = 90
